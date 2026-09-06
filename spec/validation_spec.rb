# frozen_string_literal: true

require_relative "../validation/corpus"
require_relative "../validation/chv_source"
require_relative "../validation/sweep"

RSpec.describe "validation harness" do
  let(:dictionary) { fixture("dictionary.tsv") }
  let(:corpus) { Validation::Corpus.load(fixture("synthetic_corpus.tsv")) }

  describe Validation::Distance do
    it "measures the typos this project exists to catch" do
      expect(described_class.between("flexerol", "flexeril")).to eq(1)
      expect(described_class.between("acetaminphen", "acetaminophen")).to eq(1)
    end

    it "is zero for an exact match" do
      expect(described_class.between("flexeril", "flexeril")).to eq(0)
    end

    it "reports anything past the bound as bound + 1 rather than computing it" do
      expect(described_class.between("aspirin", "acetaminophen", max: 3)).to eq(4)
    end

    it "short-circuits on a length gap alone" do
      expect(described_class.between("a", "abcdefgh", max: 2)).to eq(3)
    end
  end

  describe Validation::Corpus do
    it "parses a two-column TSV, ignoring comments and blanks" do
      expect(corpus.size).to eq(7)
      expect(corpus.pairs.first.misspelling).to eq("flexerol")
      expect(corpus.pairs.first.expected).to eq("flexeril")
    end

    it "drops pairs that are already correct, since they carry no typo signal" do
      Tempfile.create(["corpus", ".tsv"]) do |file|
        file.write("aspirin\taspirin\nasprin\taspirin\n")
        file.flush

        expect(described_class.load(file.path).size).to eq(1)
      end
    end

    it "explains the licence when the corpus is absent rather than failing obscurely" do
      expect { described_class.load("/nonexistent/corpus.tsv") }
        .to raise_error(described_class::MissingError, /not committed on purpose.*bin\/fetch_chv/m)
    end
  end

  describe Validation::ChvSource do
    let(:result) { described_class.parse(fixture("mrconso_sample.rrf")) }

    it "joins a CHV consumer string to the RxNorm name sharing its CUI" do
      expect(result.pairs["acetominophen"]).to eq("acetaminophen")
    end

    it "prefers the ingredient name over the brand name for a concept" do
      # C0001 carries both an IN (Cyclobenzaprine) and a BN (Flexeril) atom.
      expect(result.pairs["flexerol"]).to eq("cyclobenzaprine")
    end

    it "falls back to the brand name when a concept has no ingredient atom" do
      expect(result.pairs["advill"]).to eq("advil")
    end

    it "drops a CHV string identical to the RxNorm name" do
      expect(result.pairs).not_to have_key("acetaminophen")
      expect(result.identical).to eq(1)
    end

    it "drops a concept with no RxNorm atom, which is how scope stays drugs-only" do
      expect(result.pairs).not_to have_key("psoriaisis")
      expect(result.unmatched).to eq(1)
    end

    it "honours the MRCONSO suppress flag" do
      expect(result.pairs).not_to have_key("ibuprophen")
    end

    it "writes a corpus the loader can read back" do
      Dir.mktmpdir do |dir|
        path = described_class.write(result, File.join(dir, "corpus.tsv"))

        expect(Validation::Corpus.load(path).size).to eq(3)
      end
    end

    it "warns in the written file that the contents must not be committed" do
      Dir.mktmpdir do |dir|
        path = described_class.write(result, File.join(dir, "corpus.tsv"))

        expect(File.read(path)).to match(/never commit or redistribute/)
      end
    end
  end

  describe Validation::Harness do
    subject(:report) do
      checker = SpellKit::Checker.new.load!(dictionary: dictionary, edit_distance: 1)
      described_class.new(checker: checker, corpus: corpus).run
    end

    it "counts a corrected typo as a hit" do
      expect(report.hit).to eq(3)  # flexerol, acetaminphen, metformn
    end

    it "excludes a pair whose target is not in the dictionary" do
      # zzzzzzzz -> warfarin: no tuning could ever produce a term the dictionary lacks.
      expect(report.unreachable).to eq(1)
    end

    it "excludes a pair whose 'misspelling' is itself a real term" do
      # flexeril -> cyclobenzaprine is a brand/generic synonym, not a typo. Leaving a real
      # term alone is correct behaviour and must not score as a miss.
      expect(report.shadowed).to eq(1)
    end

    it "separates a wrong correction from no correction at all" do
      expect(report.wrong).to eq(1)   # atorvastatn -> atorvastatin, wanted amoxicillin
      expect(report.miss).to eq(1)    # qqqqqqqqqq, nothing within edit distance
    end

    it "scores recall and error rate over the same evaluable denominator" do
      expect(report.scored).to eq(5)
      expect(report.recall).to be_within(0.001).of(0.6)
      expect(report.error_rate).to be_within(0.001).of(0.2)
    end

    it "reports dictionary coverage separately from tuning quality" do
      expect(report.coverage).to be_within(0.001).of(5.0 / 7)
    end

    it "measures the share of pairs no edit-distance corrector could reach" do
      # The ceiling that decides whether a phonetic fallback is worth proposing.
      expect(report.beyond_edit_distance_2).to be_within(0.001).of(0.4)
    end

    it "keeps examples of wrong corrections for inspection" do
      expect(report.wrong_examples).to include(["atorvastatn", "atorvastatin", "amoxicillin"])
    end
  end

  describe Validation::Sweep do
    subject(:sweep) do
      described_class.new(dictionary: dictionary, corpus: corpus,
        edit_distances: [1, 2], thresholds: [0.0, 10.0])
    end

    it "scores every point on the grid" do
      outcomes = sweep.run

      expect(outcomes.length).to eq(4)
      expect(outcomes.map { _1.config.edit_distance }.uniq).to contain_exactly(1, 2)
    end

    it "recommends a config that clears the harm ceiling" do
      best = described_class.recommend(sweep.run, max_error_rate: 0.25)

      expect(best).not_to be_nil
      expect(best.report.error_rate).to be <= 0.25
    end

    it "recommends nothing rather than something harmful when no config clears the ceiling" do
      expect(described_class.recommend(sweep.run, max_error_rate: 0.0)).to be_nil
    end

    it "never trades harm for recall" do
      outcomes = sweep.run
      best = described_class.recommend(outcomes, max_error_rate: 0.25)
      higher_recall = outcomes.select { _1.report.recall > best.report.recall }

      expect(higher_recall).to all(satisfy { |o| o.report.error_rate > 0.25 })
    end
  end

  # The real sweep needs the UMLS-derived corpus, which is deliberately not committed.
  # Skips on a fresh clone rather than failing; runs for anyone who has built it.
  describe "against the real CHV corpus", if: Validation::Corpus.available? do
    it "produces a recommendation" do
      outcomes = Validation::Sweep.new(
        dictionary: dictionary,
        corpus: Validation::Corpus.load,
        edit_distances: [1, 2], thresholds: [0.0, 10.0]
      ).run

      expect(outcomes).not_to be_empty
    end
  end
end
