# frozen_string_literal: true

require "set"
require "json"
require "fileutils"

module Pipeline
  # Reshapes Substrate's dictionary-source export into the spellkit contract:
  # dictionary.tsv (term<TAB>frequency, frequency descending) + protected.txt.
  #
  # Two decisions carry most of the weight here.
  #
  # PHRASES MUST BE DECOMPOSED. SymSpell is a unigram index, so a multi-word row can never
  # match a typed token - and 162,605 of the 275,936 exported terms are phrases. That is not
  # merely wasteful: measured on the v10 export, "diabetes" appears ONLY inside phrases
  # ("diabetes mellitus, type 2"), so without decomposition a user typing "diabets" gets no
  # correction at all. Components are therefore emitted as their own terms.
  #
  # CURATED TERMS AND PHRASE FRAGMENTS GET DIFFERENT TRUST. A single-token export row came
  # from a curated mart and is accepted almost as-is, which is what keeps legitimate names
  # like "5-fluorouracil" that open with a digit. A fragment split out of a phrase is noisy -
  # dose units, trademark symbols, English glue - so it must clear a stricter bar.
  class PackBuilder
    # A curated term may contain digits anywhere; a fragment must start with a letter, which
    # is what rejects dose debris ("40mg", "1753") while keeping codes ("ly2157299", "cdk10").
    CURATED = /\A[a-z0-9][a-z0-9'+-]*\z/
    FRAGMENT = /\A[a-z][a-z0-9'+-]*\z/

    # Splitting a phrase: whitespace and the punctuation that separates clinical name parts.
    SPLIT = %r{[\s,;:()\[\]/]+}

    # Trademark and registered marks ride along on brand names ("genvoya®").
    TRIM = /[®™©]/

    MIN_LENGTH = 3

    attr_reader :stats

    def initialize(source:, stopwords: Set.new, floor: 1, min_length: MIN_LENGTH,
      min_fragment_df: 2)
      @source = source
      @stopwords = stopwords
      @floor = floor
      @min_length = min_length
      @min_fragment_df = min_fragment_df
      @frequencies = Hash.new(0)
      @fragment_df = Hash.new(0)
      @fragment_score = Hash.new(0)
      @protected = Set.new
      @stats = Hash.new(0)
    end

    def build
      each_row do |term, prominence, is_protected, n_tokens|
        if n_tokens == 1
          add_curated(term, prominence, is_protected)
        else
          add_phrase(term, prominence)
        end
      end

      admit_fragments

      @stats[:terms] = @frequencies.size
      @stats[:protected] = @protected.size
      self
    end

    def dictionary
      # SymSpell convention: most frequent first.
      @frequencies.sort_by { |term, frequency| [-frequency, term] }
    end

    def protected_terms
      @protected.sort
    end

    def write(directory)
      FileUtils.mkdir_p(directory)

      File.open(File.join(directory, "dictionary.tsv"), "w") do |out|
        dictionary.each { |term, frequency| out.puts "#{term}\t#{frequency}" }
      end

      File.open(File.join(directory, "protected.txt"), "w") do |out|
        out.puts "# Terms spellkit must never correct: gene/target symbols and alphanumeric"
        out.puts "# designations that look like typos of English words but are real."
        protected_terms.each { |term| out.puts term }
      end

      File.write(File.join(directory, "manifest.json"), JSON.pretty_generate(stats.sort.to_h))
      directory
    end

    private

    def each_row
      File.foreach(@source) do |line|
        next if line.start_with?("#")

        fields = line.chomp.split("\t")
        next if fields.length < 7
        next if fields[0] == "term" # header

        @stats[:source_rows] += 1
        n_tokens = fields[6].to_i
        yield fields[0], fields[1].to_i, fields[2] == "1", n_tokens
      end
    end

    # A frequency floor keeps every real term reachable. 45% of the v10 export has prominence
    # 0 (no trial signal), and spellkit's frequency_threshold would otherwise make those terms
    # unreachable as correction targets - they would be in the index but never suggested.
    def score(prominence)
      @floor + prominence
    end

    def add_curated(term, prominence, is_protected)
      token = term.gsub(TRIM, "").strip
      unless acceptable?(token, CURATED)
        @stats[:rejected_curated] += 1
        return
      end

      @stats[:from_curated] += 1
      record(token, score(prominence))
      @protected << token if is_protected
    end

    # A fragment carries only PART of its concept, so it must not inherit the concept's whole
    # weight. Without this, decomposing the MeSH root "pathological conditions, signs and
    # symptoms" (prominence 141,729 - a rollup over every descendant trial) made "signs" and
    # "symptoms" the two highest-frequency terms in the pack, outranking "neoplasms" and
    # turning category glue into the strongest correction attractors in the index. Spreading a
    # phrase's prominence across its parts keeps a head word that recurs across many phrases
    # (diabetes) high, while a generic part of one inflated rollup stays modest.
    def add_phrase(phrase, prominence)
      @stats[:phrases] += 1
      parts = phrase.gsub(TRIM, "").split(SPLIT).reject(&:empty?)
      prominence = parts.empty? ? prominence : prominence / parts.length
      parts.each do |raw|
        token = raw.strip
        next if token.empty?

        unless acceptable?(token, FRAGMENT)
          @stats[:rejected_fragment] += 1
          next
        end

        # Ordinary English glue is not domain vocabulary.
        if @stopwords.include?(token)
          @stats[:rejected_stopword] += 1
          next
        end

        # Held back until every phrase is seen, so document frequency can be counted.
        @fragment_df[token] += 1
        @fragment_score[token] = score(prominence) if score(prominence) > @fragment_score[token]
      end
    end

    # A fragment must appear in at least min_fragment_df DISTINCT phrases to earn a dictionary
    # entry. This is what keeps source typos out, and it matters more than it sounds: Substrate's
    # drug names include sponsor-typed trial intervention names, so real misspellings are present
    # in the vocabulary. "acetaminphen" reached the first build this way, and because spellkit
    # never corrects a word it can FIND - frequency_threshold governs correction targets, not
    # membership - its presence silently disabled correction of that typo entirely. A misspelling
    # in one trial title appears once; "diabetes" appears in hundreds.
    def admit_fragments
      @fragment_df.each do |token, df|
        if df < @min_fragment_df
          @stats[:rejected_rare_fragment] += 1
          next
        end

        @stats[:from_phrases] += 1
        record(token, @fragment_score[token])
      end
    end

    def acceptable?(token, pattern)
      token.length >= @min_length && token.match?(pattern) && token.match?(/[a-z]/)
    end

    # A token reachable from several entities takes the highest score, so a prominent parent
    # never loses to an obscure namesake.
    def record(token, frequency)
      @frequencies[token] = frequency if frequency > @frequencies[token]
    end
  end
end
