# frozen_string_literal: true

module SpellKit
  module Dictionaries
    # One downloadable file in a release (the dictionary.tsv or the protected.txt),
    # addressed by an immutable version-tagged URL and optionally checksummed.
    class Asset
      attr_reader :url, :sha256

      def initialize(url:, sha256: nil)
        raise RegistryError, "asset is missing a url" if url.nil? || url.to_s.empty?

        @url = url.to_s
        @sha256 = sha256&.to_s&.downcase
      end

      # Used as the last path segment of the cache key, so the cached file keeps a
      # recognisable name rather than an opaque hash.
      def filename
        name = File.basename(URI.parse(url).path.to_s)
        name.empty? ? "asset" : name
      rescue URI::InvalidURIError
        "asset"
      end

      def self.from_yaml(node, label)
        return nil if node.nil?
        raise RegistryError, "#{label} must be a mapping with a url" unless node.is_a?(Hash)

        new(url: node["url"], sha256: node["sha256"])
      end
    end

    # A published version of a pack: the tag it was cut from, its artifacts, and the
    # spellkit tuning that was validated against THAT build. Shipping the tuning with
    # the pointer is the point - edit_distance and frequency_threshold are tuned per
    # pack against a held-out corpus, so a consumer should not have to rediscover them.
    class Release
      attr_reader :tag, :released_on, :term_count, :dictionary, :protected_asset, :defaults

      def initialize(tag:, dictionary:, protected_asset: nil, released_on: nil,
        term_count: nil, defaults: {})
        raise RegistryError, "release is missing a tag" if tag.nil? || tag.to_s.empty?

        @tag = tag.to_s
        @dictionary = dictionary
        @protected_asset = protected_asset
        @released_on = released_on
        @term_count = term_count
        @defaults = defaults
      end

      def self.from_yaml(node, pack_name)
        return nil if node.nil?
        raise RegistryError, "pack #{pack_name}: release must be a mapping or null" unless node.is_a?(Hash)

        dictionary = Asset.from_yaml(node["dictionary"], "pack #{pack_name}: dictionary")
        raise RegistryError, "pack #{pack_name}: release is missing a dictionary asset" if dictionary.nil?

        new(
          tag: node["tag"],
          released_on: node["released_on"],
          term_count: node["term_count"],
          dictionary: dictionary,
          protected_asset: Asset.from_yaml(node["protected"], "pack #{pack_name}: protected"),
          defaults: symbolize(node["defaults"])
        )
      end

      # spellkit's load! takes keyword arguments, so tuning read out of YAML has to
      # arrive with symbol keys.
      def self.symbolize(node)
        return {} if node.nil?
        raise RegistryError, "release defaults must be a mapping" unless node.is_a?(Hash)

        node.each_with_object({}) { |(key, value), acc| acc[key.to_sym] = value }
      end
      private_class_method :symbolize
    end

    # A named domain vocabulary (`:medical`, `:general_medical`, ...). A Pack is a
    # POINTER plus metadata - it never holds term data itself.
    class Pack
      attr_reader :name, :summary, :built_from, :notes, :release

      def initialize(name:, summary: nil, built_from: [], notes: nil, release: nil)
        @name = name.to_s
        @summary = summary
        @built_from = built_from || []
        @notes = notes
        @release = release
      end

      def released?
        !release.nil?
      end

      # The keyword arguments to hand to SpellKit#load! for this pack, with any caller
      # overrides applied last. An override of :dictionary or :protected_path suppresses
      # the corresponding download rather than fetching a file that would be discarded.
      def load_options(fetcher: nil, **overrides)
        ensure_released!
        fetcher ||= Fetcher.new

        options = release.defaults.dup

        unless overrides.key?(:dictionary)
          options[:dictionary] = fetcher.fetch(release.dictionary, cache_key: cache_key(release.dictionary))
        end

        if release.protected_asset && !overrides.key?(:protected_path)
          options[:protected_path] = fetcher.fetch(release.protected_asset, cache_key: cache_key(release.protected_asset))
        end

        options.merge(overrides)
      end

      def self.from_yaml(name, node)
        raise RegistryError, "pack #{name} must be a mapping" unless node.is_a?(Hash)

        new(
          name: name,
          summary: node["summary"],
          built_from: node["built_from"],
          notes: node["notes"],
          release: Release.from_yaml(node["release"], name)
        )
      end

      private

      def cache_key(asset)
        File.join(name, release.tag, asset.filename)
      end

      def ensure_released!
        return if released?

        raise PackNotReleasedError,
          "The #{name.inspect} pack is registered but has no published release yet, so there is " \
          "nothing to download. Track it at https://github.com/scientist-labs/spellkit-dictionaries " \
          "or pass your own files: SpellKit.enable_dictionary(dictionary: \"...\", protected_path: \"...\")."
      end
    end
  end
end
