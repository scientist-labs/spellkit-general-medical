# frozen_string_literal: true

require_relative "lib/spellkit/dictionaries/version"

Gem::Specification.new do |spec|
  spec.name = "spellkit-dictionaries"
  spec.version = SpellKit::Dictionaries::VERSION
  spec.authors = ["Chris Petersen"]
  spec.email = ["chris@petersen.io"]

  spec.summary = "Domain dictionary packs for spellkit"
  spec.description = "Adds SpellKit.enable_dictionary(:medical) and friends to spellkit: a " \
                     "versioned registry of domain-specific dictionary and protected-term packs, " \
                     "fetched and cached on demand. Ruby only - no dictionary data ships in the gem."
  spec.homepage = "https://github.com/scientist-labs/spellkit-dictionaries"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  # data/packs.yml is the pack REGISTRY (names, urls, checksums, tuned defaults) and is
  # a few KB of pointers. It is not dictionary data: spellkit's "don't bundle dictionaries"
  # rule holds here too, and the multi-MB .tsv/.txt payloads are fetched at runtime.
  spec.files = Dir.glob(%w[
    lib/**/*.rb
    data/packs.yml
    LICENSE.txt
    README.md
    CHANGELOG.md
  ])
  spec.require_paths = ["lib"]

  # 0.3.0 is the first spellkit that installs on Ruby 4.0 without a Rust toolchain, so it
  # is the floor for anyone on Ruby 4; 0.2.0 still works fine on 3.1-3.4.
  spec.add_dependency "spellkit", ">= 0.2.0", "< 2.0"

  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "standard", "~> 1.3"
  spec.add_development_dependency "webmock", "~> 3.0"
end
