# frozen_string_literal: true

RSpec.describe SpellKit::Dictionaries::Registry do
  describe "the registry shipped with the gem" do
    it "lists the packs this gem version knows about" do
      expect(SpellKit::Dictionaries.pack_names).to include(:medical, :general_medical)
    end

    it "ships every pack with a summary, so the README catalog has something to render" do
      SpellKit::Dictionaries.packs.each_value do |pack|
        expect(pack.summary).to be_a(String), "#{pack.name} has no summary"
        expect(pack.summary).not_to be_empty
      end
    end

    it "only ever points at immutable version-tagged urls, never a 'latest' alias" do
      # spellkit caches by SHA256(url) forever, so a floating url would permanently pin
      # a consumer to their first download. See data/packs.yml's header.
      SpellKit::Dictionaries.packs.each_value do |pack|
        next unless pack.released?

        [pack.release.dictionary, pack.release.protected_asset].compact.each do |asset|
          expect(asset.url).not_to include("releases/latest/"),
            "#{pack.name} points at a floating url: #{asset.url}"
        end
      end
    end
  end

  describe ".fetch" do
    before { use_registry("packs_released.yml") }

    it "accepts a symbol, a string, and a dashed spelling of the same pack" do
      pack = described_class.fetch(:dictionary_only)

      expect(described_class.fetch("dictionary_only")).to equal(pack)
      expect(described_class.fetch("dictionary-only")).to equal(pack)
      expect(described_class.fetch("Dictionary_Only")).to equal(pack)
    end

    it "raises UnknownPackError naming the packs it does know" do
      expect { described_class.fetch(:finance) }
        .to raise_error(SpellKit::Dictionaries::UnknownPackError, /Unknown dictionary pack :finance.*demo/m)
    end

    it "explains that a newer pack may need a newer gem" do
      expect { described_class.fetch(:finance) }
        .to raise_error(SpellKit::Dictionaries::UnknownPackError, /registry ships with the gem/)
    end
  end

  describe ".key?" do
    before { use_registry("packs_released.yml") }

    it "is true for a known pack and false otherwise" do
      expect(described_class.key?(:demo)).to be true
      expect(described_class.key?(:nope)).to be false
    end
  end

  describe "parsing" do
    it "refuses a registry written against a newer schema" do
      use_registry("packs_bad_schema.yml")

      expect { described_class.packs }
        .to raise_error(SpellKit::Dictionaries::RegistryError, /schema_version 99 is not supported/)
    end

    it "reports unparseable YAML as a registry error" do
      use_registry("packs_malformed.yml")

      expect { described_class.packs }
        .to raise_error(SpellKit::Dictionaries::RegistryError, /not valid YAML/)
    end

    it "reports a missing registry file" do
      stub_const("#{described_class}::PATH", "/nonexistent/packs.yml")
      described_class.reload!

      expect { described_class.packs }
        .to raise_error(SpellKit::Dictionaries::RegistryError, /not found/)
    end
  end
end
