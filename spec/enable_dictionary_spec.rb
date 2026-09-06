# frozen_string_literal: true

RSpec.describe "SpellKit.enable_dictionary" do
  it "is added to SpellKit by this gem, without spellkit knowing packs exist" do
    expect(SpellKit).to respond_to(:enable_dictionary)
    expect(SpellKit).to respond_to(:dictionary_checker)
  end

  describe "pack resolution" do
    before { use_registry("packs_released.yml") }

    it "hands spellkit the pack's local paths and tuned defaults" do
      stub_demo_pack
      allow(SpellKit).to receive(:load!)

      SpellKit.enable_dictionary(:demo)

      expect(SpellKit).to have_received(:load!).with(
        hash_including(dictionary: end_with("dictionary.tsv"),
          protected_path: end_with("protected.txt"),
          edit_distance: 2,
          frequency_threshold: 5.0)
      )
    end

    it "lets a caller override a pack default" do
      stub_demo_pack
      allow(SpellKit).to receive(:load!)

      SpellKit.enable_dictionary(:demo, edit_distance: 1)

      expect(SpellKit).to have_received(:load!).with(hash_including(edit_distance: 1))
    end

    it "records which pack backs the default checker" do
      stub_demo_pack
      allow(SpellKit).to receive(:load!)

      SpellKit.enable_dictionary(:demo)

      expect(SpellKit.dictionary_pack.name).to eq("demo")
    end
  end

  describe "custom files" do
    it "passes straight through to spellkit without consulting the registry" do
      allow(SpellKit).to receive(:load!)
      allow(SpellKit::Dictionaries::Registry).to receive(:packs).and_call_original

      SpellKit.enable_dictionary(dictionary: fixture("dictionary.tsv"), protected_path: fixture("protected.txt"))

      expect(SpellKit).to have_received(:load!).with(
        dictionary: fixture("dictionary.tsv"), protected_path: fixture("protected.txt")
      )
      expect(SpellKit::Dictionaries::Registry).not_to have_received(:packs)
    end

    it "reports no pack when configured from custom files" do
      allow(SpellKit).to receive(:load!)

      SpellKit.enable_dictionary(dictionary: fixture("dictionary.tsv"))

      expect(SpellKit.dictionary_pack).to be_nil
    end

    it "asks for a pack name or a dictionary when given neither" do
      expect { SpellKit.enable_dictionary }
        .to raise_error(SpellKit::InvalidArgumentError, /Pass a pack name .* or a dictionary:/)
    end
  end

  describe "cache management" do
    before { use_registry("packs_released.yml") }

    it "clears one pack's artifacts without touching the rest of the cache" do
      stub_demo_pack
      SpellKit::Dictionaries.pack(:demo).load_options
      other = File.join(SpellKit::Dictionaries.cache_dir, "other", "keep.txt")
      FileUtils.mkdir_p(File.dirname(other))
      File.write(other, "keep me")

      SpellKit::Dictionaries.clear_cache!(:demo)

      expect(Dir.exist?(File.join(SpellKit::Dictionaries.cache_dir, "demo"))).to be false
      expect(File.exist?(other)).to be true
    end

    it "refuses to rm -rf a cache directory pointed at $HOME" do
      ENV[SpellKit::Dictionaries::ENV_CACHE_DIR] = Dir.home

      expect { SpellKit::Dictionaries.clear_cache! }
        .to raise_error(SpellKit::Dictionaries::Error, /Refusing to clear/)
    end
  end
end
