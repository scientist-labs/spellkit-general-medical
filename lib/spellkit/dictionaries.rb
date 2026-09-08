# frozen_string_literal: true

require "spellkit"
require "fileutils"

require_relative "dictionaries/version"
require_relative "dictionaries/errors"
require_relative "dictionaries/pack"
require_relative "dictionaries/registry"
require_relative "dictionaries/fetcher"
require_relative "dictionaries/lazy_checker"

module SpellKit
  # Domain dictionary packs for spellkit.
  #
  # This gem is a plugin: it reopens the SpellKit module from the outside to add
  # `enable_dictionary`, so spellkit's own repo, gemspec and release cadence never have
  # to know that "medical" is a thing. Everything domain-specific lives here, and the
  # dependency only ever points this way (spellkit-dictionaries -> spellkit).
  #
  # No dictionary data ships in this gem - only pointers. See data/packs.yml.
  module Dictionaries
    ENV_CACHE_DIR = "SPELLKIT_DICTIONARIES_CACHE_DIR"

    class << self
      # {"medical" => Pack, ...}
      def packs
        Registry.packs
      end

      # [:medical, :general_medical]
      def pack_names
        Registry.names.map(&:to_sym)
      end

      def pack(name)
        Registry.fetch(name)
      end

      def pack?(name)
        Registry.key?(name)
      end

      # Where fetched artifacts live. Kept separate from spellkit's own
      # ~/.cache/spellkit so clearing one never disturbs the other.
      def cache_dir
        ENV[ENV_CACHE_DIR] || File.join(Dir.home, ".cache", "spellkit-dictionaries")
      end

      # Deletes cached artifacts - the whole cache, or one pack's subtree. Safe to call
      # when nothing is cached. Loading a pack afterwards re-downloads it.
      def clear_cache!(pack_name = nil)
        target = pack_name ? File.join(cache_dir, Registry.normalize(pack_name)) : cache_dir
        guard_cache_path!(target)
        FileUtils.rm_rf(target)
        target
      end

      # Builds the keyword arguments for SpellKit#load!.
      #
      # With a pack name, resolves it through the registry (downloading and caching the
      # artifacts). With no pack name, this is a pure pass-through to spellkit and the
      # registry is not consulted at all.
      def load_options(pack_name = nil, fetcher: nil, **overrides)
        if pack_name.nil?
          unless overrides.key?(:dictionary)
            raise SpellKit::InvalidArgumentError,
              "Pass a pack name (one of #{pack_names.inspect}) or a dictionary: of your own, " \
              "e.g. SpellKit.enable_dictionary(dictionary: \"path/to/dictionary.tsv\")."
          end

          return overrides
        end

        pack(pack_name).load_options(fetcher: fetcher, **overrides)
      end

      private

      # ENV_CACHE_DIR is operator-supplied, and clear_cache! is an rm -rf. Refuse the
      # paths where a mistake would be expensive.
      def guard_cache_path!(path)
        expanded = File.expand_path(path)
        forbidden = [File.expand_path("/"), File.expand_path(Dir.home)]
        return unless forbidden.include?(expanded)

        raise Error, "Refusing to clear cache directory #{expanded}. Check #{ENV_CACHE_DIR}."
      end
    end
  end
end

require_relative "dictionaries/extension"
