# frozen_string_literal: true

require_relative "distance"

module Validation
  # Scores one loaded checker against a corpus.
  #
  # Every pair lands in exactly one bucket:
  #
  #   unreachable - the correct term is not in the dictionary at all, so no setting of
  #                 edit_distance or frequency_threshold could ever produce it. Excluded
  #                 from recall: this measures dictionary coverage, not tuning.
  #   shadowed    - the "misspelling" is itself a dictionary term. CHV lists consumer
  #                 variants, not only typos, and a real term is correctly left alone.
  #                 Also excluded - counting these as misses would punish a correct call.
  #   hit         - corrected to the expected term.
  #   wrong       - corrected to a DIFFERENT term. The harmful case: in a search box a
  #                 confident wrong correction is worse than no correction.
  #   miss        - left unchanged, no suggestion offered.
  #
  # recall and error_rate are both over (hit + wrong + miss), so they are comparable
  # across configs while dictionary coverage stays a separate number.
  class Harness
    def initialize(checker:, corpus:)
      @checker = checker
      @corpus = corpus
    end

    def run
      buckets = {hit: 0, wrong: 0, miss: 0, unreachable: 0, shadowed: 0}
      distances = Hash.new(0)
      wrong_examples = []

      @corpus.each do |pair|
        unless @checker.correct?(pair.expected)
          buckets[:unreachable] += 1
          next
        end

        if @checker.correct?(pair.misspelling)
          buckets[:shadowed] += 1
          next
        end

        distances[Distance.between(pair.misspelling, pair.expected)] += 1

        result = @checker.correct(pair.misspelling).to_s.downcase

        if result == pair.expected
          buckets[:hit] += 1
        elsif result == pair.misspelling
          buckets[:miss] += 1
        else
          buckets[:wrong] += 1
          wrong_examples << [pair.misspelling, result, pair.expected] if wrong_examples.size < 20
        end
      end

      Report.new(buckets: buckets, distances: distances, wrong_examples: wrong_examples,
        total: @corpus.size)
    end
  end

  # FALSE POSITIVES ON CORRECTLY-SPELLED INPUT.
  #
  # This exists because its absence hid a catastrophic defect for three rounds of measurement.
  # Every corpus pair is a known misspelling, so a harness built only on the corpus measures
  # recall and never asks the opposite question: what does this pack do to text that was
  # already right? The medical pack scored 89% recall while silently rewriting 87.5% of the
  # thousand most common English words - "the" -> "dhe", "and" -> "aid", "with" -> "witch" -
  # because a domain-only dictionary treats every ordinary word as an unknown to be fixed.
  #
  # Any pack intended for text that is not pre-filtered to domain terms must score ~0 here.
  class FalsePositiveCheck
    def initialize(checker:, words:)
      @checker = checker
      @words = words
    end

    def run
      considered = @words.select { |word| word.length >= 3 }
      mangled = considered.reject { |word| @checker.correct(word) == word }

      {considered: considered.size, mangled: mangled.size,
       rate: considered.empty? ? 0.0 : mangled.size.to_f / considered.size,
       examples: mangled.first(10).map { |word| [word, @checker.correct(word)] }}
    end
  end

  class Report
    attr_reader :buckets, :distances, :wrong_examples, :total

    def initialize(buckets:, distances:, wrong_examples:, total:)
      @buckets = buckets
      @distances = distances
      @wrong_examples = wrong_examples
      @total = total
    end

    def hit = buckets[:hit]

    def wrong = buckets[:wrong]

    def miss = buckets[:miss]

    def unreachable = buckets[:unreachable]

    def shadowed = buckets[:shadowed]

    # Pairs a tuning change can actually move.
    def scored
      hit + wrong + miss
    end

    def recall
      ratio(hit, scored)
    end

    # The metric to constrain, not maximize.
    def error_rate
      ratio(wrong, scored)
    end

    # How much of the corpus this DICTIONARY can speak to at all. Moves when the
    # dictionary changes, not when tuning does.
    def coverage
      ratio(scored, total)
    end

    # The share of scorable pairs sitting further from their target than any
    # edit-distance-2 corrector can reach - the hard ceiling on recall, and the number
    # that decides whether a phonetic fallback is worth proposing against spellkit's
    # Rust core (PLAN.md, "Open question: phonetic fallback").
    def beyond_edit_distance_2
      ratio(distances.sum { |d, n| (d > 2) ? n : 0 }, distances.values.sum)
    end

    private

    def ratio(numerator, denominator)
      return 0.0 if denominator.zero?

      numerator.to_f / denominator
    end
  end
end
