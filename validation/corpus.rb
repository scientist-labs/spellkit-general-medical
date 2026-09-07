# frozen_string_literal: true

require_relative "distance"

module Validation
  # A held-out set of (misspelling, correct term) pairs used to tune a pack.
  #
  # Deliberately NOT part of the shipped gem: this is build-time tooling. The corpus
  # itself is never committed either - see corpus/README.md for why.
  class Corpus
    Pair = Struct.new(:misspelling, :expected, keyword_init: true)

    DEFAULT_PATH = File.expand_path("../corpus/chv_drug_misspellings.tsv", __dir__)

    class MissingError < StandardError; end

    attr_reader :pairs, :path

    def initialize(pairs, path: nil)
      @pairs = pairs
      @path = path
    end

    def self.available?(path = DEFAULT_PATH)
      File.exist?(path)
    end

    # CHV IS NOT PURELY A MISSPELLING LIST, and assuming it is measures the wrong thing.
    # Measured on the real 2026AA release: of 5,195 drug pairs only 1,325 are
    # single-token -> single-token. The rest are word-order permutations
    # ("0 9 chloride injection sodium") and formulation restatements
    # ("0.45% sodium chloride" -> "sodium chloride 0.0769 meq/ml"). A unigram checker cannot
    # express those at all, so scoring them would count guaranteed losses as misses and drive
    # the sweep toward uselessly aggressive settings.
    #
    # Note that even the single-token remainder mixes true typos (acetobutolol ->
    # acebutolol) with morphological variants (accutanes -> accutane, 5-fluorouracil ->
    # fluorouracil). Those are legitimate normalizations for a search box, so they are kept -
    # but the corpus measures "consumer form -> canonical form", which is broader than
    # "typo -> correction". Do not report a number from it as a typo-correction rate.
    def self.load(path = DEFAULT_PATH, single_token_only: false, max_distance: nil)
      unless File.exist?(path)
        raise MissingError,
          "No validation corpus at #{path}. It is not committed on purpose (UMLS licence); " \
          "run bin/fetch_chv to rebuild it, or pass --corpus with your own two-column TSV. " \
          "See corpus/README.md."
      end

      pairs = []
      File.foreach(path) do |line|
        line = line.strip
        next if line.empty? || line.start_with?("#")

        misspelling, expected = line.split("\t", 2)
        next if misspelling.nil? || expected.nil?

        misspelling = misspelling.strip.downcase
        expected = expected.strip.downcase
        next if misspelling.empty? || expected.empty?
        # A pair that is already correct carries no signal about typo tolerance.
        next if misspelling == expected
        next if single_token_only && (misspelling.include?(" ") || expected.include?(" "))
        # ORTHOGRAPHIC PAIRS ONLY, when asked. CHV maps consumer terms to concepts by MEANING,
        # so it contains abbreviations an edit-distance corrector can never reach: adr ->
        # doxorubicin, na -> sodium, cyts -> cyclophosphamide. Scoring those punishes the
        # checker for a task it is not attempting and inflates the apparent error rate, which
        # then drags the recommended threshold up to a setting that corrects nothing at all.
        next if max_distance && Distance.between(misspelling, expected, max: max_distance) > max_distance

        pairs << Pair.new(misspelling: misspelling, expected: expected)
      end

      new(pairs, path: path)
    end

    def size
      pairs.size
    end

    def each(&block)
      pairs.each(&block)
    end
  end
end
