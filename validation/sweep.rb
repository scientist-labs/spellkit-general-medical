# frozen_string_literal: true

require "spellkit"
require_relative "harness"

module Validation
  # Grid search over the two spellkit knobs that change correction behaviour, scored
  # against a held-out corpus. This is what turns PLAN.md's "needs empirical tuning" into
  # two numbers that ship in data/packs.yml.
  class Sweep
    Config = Struct.new(:edit_distance, :frequency_threshold, keyword_init: true) do
      def to_s
        "edit_distance=#{edit_distance} frequency_threshold=#{frequency_threshold}"
      end
    end

    Outcome = Struct.new(:config, :report, keyword_init: true)

    # spellkit accepts only 1 or 2 for edit_distance and validates it, so the grid is the
    # whole space on that axis.
    EDIT_DISTANCES = [1, 2].freeze
    THRESHOLDS = [0.0, 1.0, 10.0, 100.0, 1000.0].freeze

    def initialize(dictionary:, corpus:, protected_path: nil,
      edit_distances: EDIT_DISTANCES, thresholds: THRESHOLDS)
      @dictionary = dictionary
      @corpus = corpus
      @protected_path = protected_path
      @edit_distances = edit_distances
      @thresholds = thresholds
    end

    def configs
      @edit_distances.product(@thresholds).map do |edit_distance, threshold|
        Config.new(edit_distance: edit_distance, frequency_threshold: threshold)
      end
    end

    def run
      configs.map do |config|
        yield config if block_given?
        Outcome.new(config: config, report: Harness.new(checker: checker_for(config), corpus: @corpus).run)
      end
    end

    # Best recall among the configs whose error rate clears the ceiling. Recall is
    # maximized SUBJECT TO harm, never traded against it: a config that corrects more
    # typos by also corrupting more real terms is not an improvement in a search box.
    def self.recommend(outcomes, max_error_rate: 0.02)
      eligible = outcomes.select { |outcome| outcome.report.error_rate <= max_error_rate }
      return nil if eligible.empty?

      eligible.max_by do |outcome|
        [
          outcome.report.recall,
          -outcome.config.edit_distance,       # cheaper index wins a tie
          outcome.config.frequency_threshold   # then the more conservative threshold
        ]
      end
    end

    private

    def checker_for(config)
      options = {
        dictionary: @dictionary,
        edit_distance: config.edit_distance,
        frequency_threshold: config.frequency_threshold
      }
      options[:protected_path] = @protected_path if @protected_path

      SpellKit::Checker.new.load!(**options)
    end
  end
end
