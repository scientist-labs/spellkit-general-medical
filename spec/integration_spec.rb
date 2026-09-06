# frozen_string_literal: true

# End to end against the real spellkit native extension: a pack is fetched over HTTP,
# cached, and loaded, and the corrections it then makes are the ones a biomedical pack
# exists to make.
RSpec.describe "loading a pack into spellkit" do
  before do
    use_registry("packs_released.yml")
    stub_demo_pack
  end

  after { SpellKit.default = nil }

  describe "the default checker" do
    before { SpellKit.enable_dictionary(:demo) }

    # The typos that started this project (see PLAN.md, "Validation"). These are a
    # permanent smoke test, not an illustration.
    it "corrects real drug-name misspellings to the real drug name" do
      expect(SpellKit.correct("flexerol")).to eq("flexeril")
      expect(SpellKit.correct("flexiril")).to eq("flexeril")
      expect(SpellKit.correct("acetaminphen")).to eq("acetaminophen")
    end

    it "recognises a term the pack ships" do
      expect(SpellKit.correct?("cyclobenzaprine")).to be true
    end

    it "never corrects a protected gene symbol" do
      expect(SpellKit.correct("CDK10")).to eq("CDK10")
      expect(SpellKit.correct("BRCA1")).to eq("BRCA1")
    end

    it "applies the pack's own edit_distance rather than spellkit's default" do
      expect(SpellKit.stats["edit_distance"] || SpellKit.stats[:edit_distance]).to eq(2)
    end
  end

  describe "an independent checker" do
    it "loads a pack without disturbing the default checker" do
      SpellKit.enable_dictionary(dictionary: fixture("dictionary.tsv"))
      default = SpellKit.default

      checker = SpellKit.dictionary_checker(:demo)

      expect(checker).to be_a(SpellKit::Checker)
      expect(checker.correct("flexerol")).to eq("flexeril")
      expect(SpellKit.default).to equal(default)
    end
  end

  describe "loading twice" do
    it "reuses the cached artifacts rather than re-downloading" do
      SpellKit.enable_dictionary(:demo)
      SpellKit.enable_dictionary(:demo)

      expect(a_request(:get, %r{demo-v1/dictionary\.tsv})).to have_been_made.once
    end
  end
end
