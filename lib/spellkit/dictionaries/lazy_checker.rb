# frozen_string_literal: true

module SpellKit
  module Dictionaries
    # A checker that has not loaded yet.
    #
    # WHY THIS EXISTS. A Rails initializer runs for EVERY process that boots the app -
    # web, `db:migrate`, `rake`, `console`, a sidecar - but usually only the web server
    # ever spell-checks anything. Loading eagerly makes every one of those processes pay
    # the full cost, which for general_medical at edit_distance 2 is ~2 GiB of resident
    # memory and several seconds. That is not theoretical: it OOM-killed a
    # memory-constrained migrate init container in production.
    #
    # WHAT IS DEFERRED. Everything: the registry lookup's network fetch, the disk read,
    # and the SymSpell index build. Deferring only the index build would still leave a
    # migrate container doing HTTP at boot, which is its own failure mode on a locked-down
    # network. The pack NAME is still validated eagerly, so a typo fails at boot where it
    # belongs rather than on a user's first search.
    #
    # WHAT DOES NOT TRIGGER A LOAD. `stats` and `healthcheck` deliberately do not force
    # one, and this matters more than it looks: a Kubernetes liveness probe hitting a
    # health endpoint would otherwise materialise the whole index in exactly the process
    # this class exists to protect, quietly reintroducing the bug. They report the
    # deferred state instead.
    #
    # THREAD SAFETY. A threaded web server can take two concurrent first requests, and
    # without the mutex both would build a multi-gigabyte index at once. The load runs at
    # most once.
    class LazyChecker
      # Lookups have to have a real index; introspection deliberately must not build one.
      FORCES_LOAD = %i[correct correct? suggestions correct_tokens].freeze

      attr_reader :pack_name

      def initialize(pack_name, options)
        @pack_name = pack_name
        @options = options
        @mutex = Mutex.new
        @checker = nil
      end

      def loaded?
        !@checker.nil?
      end

      # Build the index now. Idempotent, and safe to call from several threads.
      #
      # Call this from a web-server boot hook (Puma's `on_worker_boot`) if you would
      # rather the SERVER pay the cost than the first user request: lazy loading moves the
      # cost, it does not remove it, and for a web process moving it onto a request is
      # usually the wrong trade.
      def load_now!
        return @checker if @checker

        @mutex.synchronize do
          # Re-check inside the lock: another thread may have loaded while we waited.
          @checker ||= SpellKit::Checker.new.load!(**Dictionaries.load_options(@pack_name, **@options))
        end
      end

      FORCES_LOAD.each do |name|
        define_method(name) { |*args| load_now!.public_send(name, *args) }
      end

      def stats
        return {"loaded" => false, "deferred" => true, "pack" => @pack_name&.to_s} unless loaded?

        @checker.stats
      end

      def healthcheck
        return {"loaded" => false, "deferred" => true, "pack" => @pack_name&.to_s} unless loaded?

        @checker.healthcheck
      end

      # Anything else a caller reaches for is a real Checker method; loading is the only
      # way to answer it honestly.
      def method_missing(name, *args, &block)
        if SpellKit::Checker.method_defined?(name)
          load_now!.public_send(name, *args, &block)
        else
          super
        end
      end

      def respond_to_missing?(name, include_private = false)
        SpellKit::Checker.method_defined?(name) || super
      end
    end
  end
end
