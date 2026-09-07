# frozen_string_literal: true

require_relative "../pipeline/pack_builder"

RSpec.describe Pipeline::PackBuilder do
  subject(:builder) do
    described_class.new(source: fixture("dictionary_source.tsv"),
      stopwords: Set["small", "type"], floor: 1).build
  end

  let(:terms) { builder.dictionary.to_h }

  describe "curated single-token terms" do
    it "admits them with frequency floored above their prominence" do
      expect(terms["flexeril"]).to eq(18) # floor 1 + prominence 17
    end

    it "keeps a legitimate name that opens with a digit" do
      # 5-fluorouracil is a real drug; the strict start-with-a-letter rule applies only to
      # noisy phrase fragments, never to a curated mart name.
      expect(terms).to have_key("5-fluorouracil")
    end

    it "strips trademark marks that ride along on brand names" do
      expect(terms).to have_key("genvoya")
      expect(terms).not_to have_key("genvoya®")
    end

    it "rejects a term too short to be a safe correction target" do
      expect(terms).not_to have_key("xy")
    end

    it "carries the protected flag through to the protected list" do
      expect(builder.protected_terms).to include("cdk10")
      expect(builder.protected_terms).not_to include("flexeril")
    end

    it "keeps protected terms in the dictionary too, so correct? recognises them" do
      expect(terms).to have_key("cdk10")
    end
  end

  describe "phrase decomposition" do
    it "emits component tokens, because SymSpell is a unigram index" do
      # Measured on the real v10 export: "diabetes" exists ONLY inside phrases, so without
      # this a user typing "diabets" gets nothing.
      expect(terms).to have_key("diabetes")
    end

    it "spreads a phrase's prominence across its parts rather than duplicating it" do
      # "diabetes mellitus type 2" is prominence 400 over 4 parts -> 100, +1 floor.
      # Without the split it would be 401, and on the real export this is what stopped the
      # MeSH root category's rollup from making "signs" and "symptoms" the two
      # highest-frequency terms in the whole pack.
      expect(terms["diabetes"]).to eq(101)
    end

    it "does not let a fragment inherit its parent's whole weight" do
      expect(terms["diabetes"]).to be < 400
    end

    it "drops ordinary English glue" do
      expect(terms).not_to have_key("small")
      expect(terms).not_to have_key("type")
    end

    it "drops dose debris and bare numbers" do
      expect(terms.keys).not_to include("500", "mg", "2")
    end
  end

  describe "the fragment document-frequency floor" do
    it "admits a fragment that appears in more than one phrase" do
      expect(terms).to have_key("rna")     # both rna phrases
      expect(terms).to have_key("diabetes") # both diabetes phrases
    end

    it "rejects a fragment seen in only one phrase" do
      # This is what keeps SOURCE TYPOS out. Substrate's drug names include sponsor-typed
      # trial intervention names, so "acetaminphen 500 mg tablet" is real input. Admitting
      # that fragment silently disables correction of the typo, because spellkit never
      # corrects a word it can find - frequency_threshold governs targets, not membership.
      expect(terms).not_to have_key("acetaminphen")
      expect(terms).not_to have_key("nucleolar")
    end

    it "also drops legitimate rare vocabulary, which is the cost of the rule" do
      # "insipidus" is a real medical word, but it occurs in exactly one source phrase and is
      # therefore indistinguishable from a one-off typo by this rule. Recorded as a known
      # trade-off, not an oversight: --min-fragment-df 1 disables it, at the price of
      # readmitting source typos. Which side to err on is what the CHV sweep decides.
      expect(terms).not_to have_key("insipidus")
    end

    it "counts the rejection so a build can report what it dropped" do
      expect(builder.stats[:rejected_rare_fragment]).to be > 0
    end
  end

  describe "provenance" do
    it "drops an uncurated term one edit from a curated one, as a suspected typo" do
      # Down-weighting cannot fix this case: spellkit never corrects a word it can FIND, so a
      # typo in the index blocks correction of itself no matter how low its frequency.
      expect(terms).to have_key("bromocriptine")
      expect(terms).not_to have_key("bromocriptin")
      expect(builder.stats[:dropped_suspected_typo]).to eq(1)
    end

    it "keeps an uncurated term that is near nothing curated, since novelty is not error" do
      expect(terms).to have_key("novelcompound")
    end

    it "down-weights an uncurated term rather than dropping it outright" do
      # 23,457 of 37,393 single-token drug terms are uncurated; excluding them wholesale would
      # cost more coverage than the typos are worth.
      expect(terms["novelcompound"]).to be < terms["flexeril"]
    end
  end

  describe "reading the export" do
    it "refuses a headerless file instead of silently writing an empty dictionary" do
      Tempfile.create(["src", ".tsv"]) do |file|
        file.write("flexeril\t17\t0\t\tdrug\t1\trxnorm_ingredient\t1\t1\n")
        file.flush

        expect { described_class.new(source: file.path).build }
          .to raise_error(ArgumentError, /no header row/)
      end
    end

    it "reads by header name, so a new export column cannot shift the parse" do
      expect(terms).to have_key("flexeril") # n_tokens moved from index 6 to 8
    end
  end

  describe "output" do
    it "writes dictionary.tsv frequency-descending, per SymSpell convention" do
      Dir.mktmpdir do |dir|
        builder.write(dir)
        frequencies = File.readlines(File.join(dir, "dictionary.tsv")).map { _1.split("\t")[1].to_i }

        expect(frequencies).to eq(frequencies.sort.reverse)
      end
    end

    it "writes a protected.txt spellkit can load" do
      Dir.mktmpdir do |dir|
        builder.write(dir)
        body = File.read(File.join(dir, "protected.txt"))

        expect(body).to start_with("#")
        expect(body).to include("cdk10")
      end
    end
  end
end
