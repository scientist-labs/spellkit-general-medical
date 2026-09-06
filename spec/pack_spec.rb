# frozen_string_literal: true

RSpec.describe SpellKit::Dictionaries::Pack do
  before { use_registry("packs_released.yml") }

  let(:demo) { SpellKit::Dictionaries.pack(:demo) }

  describe "#released?" do
    it "is true for a pack with published artifacts" do
      expect(demo.released?).to be true
    end

    it "is false for a registered but unpublished pack" do
      expect(SpellKit::Dictionaries.pack(:unreleased).released?).to be false
    end
  end

  describe "#load_options" do
    it "returns local paths for both artifacts plus the pack's tuned defaults" do
      stub_demo_pack

      options = demo.load_options

      expect(File.read(options[:dictionary])).to eq(fixture_body("dictionary.tsv"))
      expect(File.read(options[:protected_path])).to eq(fixture_body("protected.txt"))
      expect(options[:edit_distance]).to eq(2)
      expect(options[:frequency_threshold]).to eq(5.0)
    end

    it "lets a caller override the pack's tuned defaults" do
      stub_demo_pack

      options = demo.load_options(edit_distance: 1, frequency_threshold: 99.0)

      expect(options[:edit_distance]).to eq(1)
      expect(options[:frequency_threshold]).to eq(99.0)
    end

    it "passes unrelated spellkit keywords straight through" do
      stub_demo_pack

      options = demo.load_options(skip_urls: true, protected_patterns: [/\A[A-Z]{3,4}\d+\z/])

      expect(options[:skip_urls]).to be true
      expect(options[:protected_patterns].length).to eq(1)
    end

    it "does not download an artifact the caller is overriding anyway" do
      # Only the protected half is stubbed; requesting the dictionary would raise.
      stub_request(:get, "https://example.test/releases/download/demo-v1/protected.txt")
        .to_return(status: 200, body: fixture_body("protected.txt"))

      options = demo.load_options(dictionary: "/my/own/dictionary.tsv")

      expect(options[:dictionary]).to eq("/my/own/dictionary.tsv")
      expect(a_request(:get, %r{demo-v1/dictionary\.tsv})).not_to have_been_made
    end

    it "omits protected_path for a pack that publishes no protected-terms file" do
      stub_request(:get, "https://example.test/releases/download/dictionary-only-v1/dictionary.tsv")
        .to_return(status: 200, body: fixture_body("dictionary.tsv"))

      options = SpellKit::Dictionaries.pack(:dictionary_only).load_options

      expect(options).not_to have_key(:protected_path)
      expect(options[:dictionary]).to be_a(String)
    end

    it "caches each artifact under pack/tag/filename so versions never collide" do
      stub_demo_pack

      options = demo.load_options
      relative = options[:dictionary].delete_prefix(SpellKit::Dictionaries.cache_dir + "/")

      expect(relative).to eq("demo/demo-v1/dictionary.tsv")
    end

    it "raises PackNotReleasedError, not a 404, for an unpublished pack" do
      expect { SpellKit::Dictionaries.pack(:unreleased).load_options }
        .to raise_error(SpellKit::Dictionaries::PackNotReleasedError, /no published release yet/)
    end

    it "points at the custom-file escape hatch when a pack is unpublished" do
      expect { SpellKit::Dictionaries.pack(:unreleased).load_options }
        .to raise_error(SpellKit::Dictionaries::PackNotReleasedError, /enable_dictionary\(dictionary:/)
    end
  end
end
