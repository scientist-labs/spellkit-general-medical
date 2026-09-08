# frozen_string_literal: true

# Reopens SpellKit to add the pack-aware entry points. This is the whole plugin seam:
# spellkit is not modified, patched or wrapped - its namespace is simply extended from
# the outside, the same way many gems reopen a host library's module.
#
# Both methods end by calling spellkit's own public load! API, so spellkit keeps doing
# all the actual loading, indexing and hot-reload work exactly as it does today.
module SpellKit
  class << self
    # Configures the DEFAULT checker from a pack, so plain SpellKit.correct("...")
    # becomes domain-aware.
    #
    #   SpellKit.enable_dictionary(:medical)
    #   SpellKit.enable_dictionary(:medical, edit_distance: 2)
    #   SpellKit.enable_dictionary(dictionary: "my.tsv", protected_path: "my.txt")
    #
    # Any keyword spellkit's load! accepts may be passed and wins over the pack's own
    # tuned defaults. Returns the configured checker.
    # Pass `lazy: true` to register the pack without loading it. See LazyChecker for why
    # that matters in a Rails app; the short version is that an initializer runs in every
    # process that boots the app, not just the one that searches.
    #
    #   SpellKit.enable_dictionary(:general_medical, lazy: true)
    #
    # Eager stays the default, so existing callers are unaffected.
    def enable_dictionary(pack = nil, lazy: false, **options)
      # Resolve the pack eagerly even when lazy, so a bad name or an unreleased pack
      # raises at boot where it is cheap to notice, not on a user's first search. This is
      # a registry lookup only - it does not fetch anything.
      @dictionary_pack = pack.nil? ? nil : Dictionaries.pack(pack)
      # Fail at boot on an unreleased pack even when lazy. The registry lookup above
      # SUCCEEDS for one (it is registered, just unpublished), so without this a lazy
      # caller would deploy clean and blow up on a user's first search instead.
      @dictionary_pack&.ensure_released! if lazy

      self.default = if lazy
        Dictionaries::LazyChecker.new(pack, options)
      else
        load!(**Dictionaries.load_options(pack, **options))
      end
    end

    # True once the default checker holds a real index. A lazily-registered pack reports
    # false until something forces the load.
    def dictionary_loaded?
      checker = @default
      return false if checker.nil?
      return checker.loaded? if checker.is_a?(Dictionaries::LazyChecker)

      true
    end

    # Force a deferred load now. Idempotent, and a no-op for an eagerly-loaded checker.
    #
    # Use it in a web-server boot hook when you would rather the server pay the cost than
    # the first request:
    #
    #   # config/puma.rb
    #   on_worker_boot { SpellKit.load_dictionary! }
    #
    # Lazy loading MOVES the cost, it does not remove it. For a web process, moving it
    # onto a user request is usually the wrong trade; for migrate/rake/console it is
    # exactly right, and those never call this.
    def load_dictionary!
      checker = @default
      checker.load_now! if checker.is_a?(Dictionaries::LazyChecker)
      checker
    end

    # Builds an INDEPENDENT checker from a pack, for running more than one domain at
    # once. This is spellkit's existing multi-instance API with the pack lookup done
    # for you; it does not touch the default checker.
    #
    #   medical = SpellKit.dictionary_checker(:medical)
    #   medical.correct("acetaminphen")
    def dictionary_checker(pack = nil, lazy: false, **options)
      resolved = pack.nil? ? nil : Dictionaries.pack(pack)
      if lazy
        resolved&.ensure_released!
        return Dictionaries::LazyChecker.new(pack, options)
      end

      Checker.new.load!(**Dictionaries.load_options(pack, **options))
    end

    # The pack backing the default checker, or nil if it was configured some other way.
    # Useful in a healthcheck or boot log.
    attr_reader :dictionary_pack
  end
end
