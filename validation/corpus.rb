# frozen_string_literal: true

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

    def self.load(path = DEFAULT_PATH)
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
