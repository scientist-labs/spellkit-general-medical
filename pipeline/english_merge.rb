# frozen_string_literal: true

require_relative "english_stopwords"

module Pipeline
  # Merges a domain pack onto spellkit's English word list to produce the general_medical
  # variant: one checker that understands both "acetaminophen" and "the".
  #
  # THE WHOLE PROBLEM IS THAT THE TWO SCALES ARE UNRELATED. Measured on the real v10 pack and
  # spellkit's en-80k list:
  #
  #            median      p90          max
  #   english  192,427     3,685,854    26,548,583,149
  #   medical  1           10           105,604
  #
  # Concatenating them puts EVERY medical term below the 1st percentile of English (4,494), so
  # a frequency_threshold sized for English makes the entire domain vocabulary unreachable as
  # correction targets, and any ambiguous typo resolves to the English word every time. That is
  # the "medical terms drown" failure PLAN.md predicted, and it is a property of the scales, not
  # of the tuning.
  #
  # So medical frequencies are rescaled - log-linearly, which preserves their ordering - into an
  # explicit band of the English distribution. The band is the policy: its floor decides whether
  # a medical term can outrank a rare English word, its ceiling whether it can outrank a common
  # one.
  #
  # THE DEFAULT BAND IS A STARTING GUESS, NOT A MEASUREMENT. p10..p90 is chosen so a domain term
  # beats rare English but never common English. Which band is actually right is exactly what the
  # CHV sweep is for; treat these numbers as provisional until it has run.
  class EnglishMerge
    DEFAULT_LOW_PERCENTILE = 10
    DEFAULT_HIGH_PERCENTILE = 90

    attr_reader :stats

    def initialize(english_path: EnglishStopwords::CACHE,
      low_percentile: DEFAULT_LOW_PERCENTILE, high_percentile: DEFAULT_HIGH_PERCENTILE)
      @english_path = english_path
      @low_percentile = low_percentile
      @high_percentile = high_percentile
      @stats = {}
    end

    # domain: [[term, frequency], ...]. Returns the merged list, frequency descending.
    def merge(domain)
      english = load_english
      band = percentile_band(english.values)
      scaled = rescale(domain, band)

      merged = english.dup
      overlap = 0
      scaled.each do |term, frequency|
        if merged.key?(term)
          overlap += 1
          # A word that is BOTH ordinary English and a domain term keeps its English weight when
          # that is higher: "cell" is a common word first and a biology term second, and demoting
          # it would make everyday text correct badly.
          merged[term] = frequency if frequency > merged[term]
        else
          merged[term] = frequency
        end
      end

      @stats = {
        english_terms: english.size,
        domain_terms: domain.size,
        overlap: overlap,
        merged_terms: merged.size,
        band_low: band.first,
        band_high: band.last
      }

      merged.sort_by { |term, frequency| [-frequency, term] }
    end

    private

    def load_english
      raise "English list not found at #{@english_path}; run bin/build_pack once to fetch it" unless File.exist?(@english_path)

      words = {}
      File.foreach(@english_path) do |line|
        term, frequency = line.split(/\s+/)
        next if term.nil? || frequency.nil?

        words[term.downcase] = frequency.to_i
      end
      words
    end

    def percentile_band(frequencies)
      sorted = frequencies.sort
      [pick(sorted, @low_percentile), pick(sorted, @high_percentile)]
    end

    def pick(sorted, percentile)
      sorted[[(sorted.length * percentile / 100), sorted.length - 1].min]
    end

    # Log-linear, so the domain's own ordering survives and its dynamic range is compressed
    # into the band rather than clipped at the ends.
    def rescale(domain, band)
      low, high = band
      frequencies = domain.map(&:last)
      min = frequencies.min.to_f
      max = frequencies.max.to_f
      span = Math.log(max) - Math.log(min)

      domain.map do |term, frequency|
        # A domain with one distinct frequency carries no ranking information, so it lands at
        # the FLOOR of the band, not the ceiling: undifferentiated terms must not outrank
        # common English just because they are all equally weighted.
        position = span.zero? ? 0.0 : (Math.log(frequency) - Math.log(min)) / span
        [term, (low * ((high.to_f / low)**position)).round]
      end
    end
  end
end
