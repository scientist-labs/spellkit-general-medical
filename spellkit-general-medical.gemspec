# frozen_string_literal: true

require_relative "lib/spellkit/general_medical/version"

Gem::Specification.new do |spec|
  spec.name = "spellkit-general-medical"
  spec.version = SpellKit::GeneralMedical::VERSION
  spec.authors = ["Chris Petersen"]
  spec.email = ["chris@petersen.io"]

  spec.summary = "Biomedical + general English dictionary pack for spellkit"
  spec.description = "Drug, condition, gene and target vocabulary merged with general " \
                     "English, as a spellkit dictionary pack. Registers itself on load, " \
                     "so SpellKit.enable_dictionary(:general_medical) just works. Ships " \
                     "tuning measured against a held-out corpus of real consumer misspellings."
  spec.homepage = "https://github.com/scientist-labs/spellkit-general-medical"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  # The DATA ships in the gem, deliberately. An earlier design fetched it over HTTP at
  # runtime, which bought nothing (the pack registry shipped in a gem anyway, so a pack
  # release already required a gem release) and cost a network dependency on the boot path,
  # a cache directory, checksum machinery, and two failure modes consumers had to handle.
  # ~1.3 MB packaged is a fair price for none of that.
  spec.files = Dir.glob(%w[
    lib/**/*.rb
    data/dictionary.tsv
    data/protected.txt
    LICENSE.txt
    README.md
    CHANGELOG.md
    ATTRIBUTION.md
  ])
  spec.require_paths = ["lib"]

  # 1.0 is the first spellkit with SpellKit::Packs, which this gem registers itself with.
  spec.add_dependency "spellkit", ">= 1.0", "< 2.0"

  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "standard", "~> 1.3"
end
