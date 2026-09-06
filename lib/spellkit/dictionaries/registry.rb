# frozen_string_literal: true

require "yaml"

module SpellKit
  module Dictionaries
    # The pack catalog shipped with this gem version. Reads data/packs.yml once and
    # memoizes; see that file's header for why the registry is versioned WITH the gem
    # rather than fetched at runtime.
    module Registry
      SCHEMA_VERSION = 1
      PATH = File.expand_path("../../../data/packs.yml", __dir__)

      class << self
        # {"medical" => Pack, ...}
        def packs
          @packs ||= load_packs
        end

        def names
          packs.keys
        end

        def fetch(name)
          key = normalize(name)
          packs.fetch(key) do
            raise UnknownPackError,
              "Unknown dictionary pack #{name.inspect}. This version of spellkit-dictionaries " \
              "(#{VERSION}) knows: #{names.map(&:to_sym).inspect}. A newer pack may need a newer " \
              "gem version, since the registry ships with the gem."
          end
        end

        def key?(name)
          packs.key?(normalize(name))
        end

        # Test hook: drop the memoized catalog so a spec can point PATH elsewhere.
        def reload!
          @packs = nil
        end

        # :medical, "medical" and "general-medical" all address the same pack.
        def normalize(name)
          name.to_s.strip.downcase.tr("-", "_")
        end

        private

        def load_packs
          raise RegistryError, "Pack registry not found at #{PATH}" unless File.exist?(PATH)

          document = begin
            YAML.safe_load_file(PATH)
          rescue Psych::SyntaxError => e
            raise RegistryError, "Pack registry at #{PATH} is not valid YAML: #{e.message}"
          end

          raise RegistryError, "Pack registry at #{PATH} must be a mapping" unless document.is_a?(Hash)

          schema = document["schema_version"]
          unless schema == SCHEMA_VERSION
            raise RegistryError,
              "Pack registry schema_version #{schema.inspect} is not supported by " \
              "spellkit-dictionaries #{VERSION} (expected #{SCHEMA_VERSION})."
          end

          entries = document["packs"]
          raise RegistryError, "Pack registry at #{PATH} has no `packs` mapping" unless entries.is_a?(Hash)

          entries.each_with_object({}) do |(name, node), acc|
            key = normalize(name)
            acc[key] = Pack.from_yaml(key, node)
          end
        end
      end
    end
  end
end
