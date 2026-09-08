# frozen_string_literal: true

RSpec.describe "spellkit-general-medical" do
  describe "registration" do
    it "registers itself with SpellKit when the gem loads" do
      # Bundler requires the gem, the gem registers the pack. A consumer names it in the
      # Gemfile and nothing else.
      expect(SpellKit::Packs.registered?(:general_medical)).to be true
    end

    it "ships the tuning measured against its own data" do
      defaults = SpellKit::Packs.fetch(:general_medical).defaults

      expect(defaults[:edit_distance]).to eq(2)
      expect(defaults[:frequency_threshold]).to eq(1.0)
    end

    it "describes itself for a catalog or a boot log" do
      expect(SpellKit::Packs.fetch(:general_medical).summary).to match(/English/)
    end
  end

  describe "the shipped data" do
    let(:pack) { SpellKit::Packs.fetch(:general_medical) }

    it "vendors the dictionary in the gem, with no network needed" do
      expect(File.exist?(pack.dictionary)).to be true
    end

    it "vendors the protected-terms list too" do
      expect(File.exist?(pack.protected_path)).to be true
    end

    it "keeps the declared term count honest" do
      # A constant that drifts from the file it describes is worse than no constant: this
      # is what a boot log or healthcheck would report.
      expect(File.foreach(pack.dictionary).count).to eq(SpellKit::GeneralMedical::TERM_COUNT)
    end

    it "keeps the declared protected count honest" do
      # protected.txt carries two leading comment lines.
      actual = File.foreach(pack.protected_path).count { |line| !line.start_with?("#") }

      expect(actual).to eq(SpellKit::GeneralMedical::PROTECTED_COUNT)
    end

    it "is sorted frequency-descending, as SymSpell expects" do
      frequencies = File.foreach(pack.dictionary).first(500).map { _1.split("\t")[1].to_i }

      expect(frequencies).to eq(frequencies.sort.reverse)
    end
  end

  describe "loaded behaviour" do
    before { SpellKit.enable_dictionary(:general_medical) }

    it "corrects biomedical misspellings a general English checker cannot" do
      # These are the ones an 80k English word list does NOT carry - brand names and
      # newer drugs - which is what the pack is for.
      expect(SpellKit.correct("flexerol")).to eq("flexeril")
      expect(SpellKit.correct("semaglutid")).to eq("semaglutide")
      expect(SpellKit.correct("pembrolizmab")).to eq("pembrolizumab")
    end

    it "leaves ordinary English alone" do
      # The domain-only variant rewrites ~87% of common English. This pack is merged with
      # an English word list precisely so it does not, and that is the property that makes
      # it safe to put in front of arbitrary user input.
      %w[the and with that from this].each do |word|
        expect(SpellKit.correct(word)).to eq(word)
      end
    end

    it "never alters a protected gene symbol" do
      %w[CDK10 BRCA1 EGFR TP53].each do |symbol|
        expect(SpellKit.correct(symbol)).to eq(symbol)
      end
    end
  end

  describe "lazy loading" do
    it "defers the index build, for Rails initializers" do
      SpellKit.enable_dictionary(:general_medical, lazy: true)

      expect(SpellKit.dictionary_loaded?).to be false
      expect(SpellKit.stats).to include("deferred" => true)
    end
  end
end
