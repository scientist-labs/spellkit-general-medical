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
      min_fragment_df: 2, uncurated_weight: 0.1, drop_uncurated_near_curated: true)
      @source = source
      @stopwords = stopwords
      @floor = floor
      @min_length = min_length
      @min_fragment_df = min_fragment_df
      @uncurated_weight = uncurated_weight
      @drop_near = drop_uncurated_near_curated
      @curated_terms = Set.new
      @uncurated_terms = Set.new
      @frequencies = Hash.new(0)
      @fragment_df = Hash.new(0)
      @fragment_score = Hash.new(0)
      @protected = Set.new
      @stats = Hash.new(0)
    end

    def build
      each_row do |term, prominence, is_protected, n_tokens, curated|
        if n_tokens == 1
          add_term(term, prominence, is_protected, curated)
        else
          add_phrase(term, prominence, curated)
        end
      end

      admit_fragments
      drop_suspected_typos

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

    # Read by HEADER NAME, not position: the export grew a `curated` and a `name_type` column
    # between the first build and the second, which shifted n_tokens from index 6 to 8. Reading
    # positionally would have silently mis-parsed every row rather than failing.
    def each_row
      header = nil

      File.foreach(@source) do |line|
        next if line.start_with?("#")

        fields = line.chomp.split("\t")
        if header.nil?
          # FAIL LOUDLY on a headerless file. Without this the first DATA row is consumed as
          # the header, every lookup returns nil, and the build reports a cheerful success
          # having written an empty dictionary - which is exactly what happened when the
          # export was produced by piping the SQL straight into psql instead of running the
          # script that writes the header.
          unless fields.include?("term")
            raise ArgumentError,
              "#{@source} has no header row (expected a line containing 'term'). Got: " \
              "#{fields.first(4).inspect}. If you produced this by piping --print-sql into " \
              "psql, prepend the header that bin/export_dictionary_source.rb writes."
          end

          header = fields.each_with_index.to_h
          next
        end

        at = ->(name) { (index = header[name]) && fields[index] }
        term = at.call("term")
        next if term.nil? || term.empty?

        @stats[:source_rows] += 1
        # `curated` is absent from a pre-provenance export; treat that as curated so an older
        # file builds unchanged rather than having every term silently down-weighted.
        curated = at.call("curated").nil? || at.call("curated") == "1"
        yield term, at.call("prominence").to_i, at.call("protected") == "1",
          at.call("n_tokens").to_i, curated
      end
    end

    # A frequency floor keeps every real term reachable. 45% of the v10 export has prominence
    # 0 (no trial signal), and spellkit's frequency_threshold would otherwise make those terms
    # unreachable as correction targets - they would be in the index but never suggested.
    # PROVENANCE AS A FREQUENCY PRIOR, not a filter. A name vouched for only by
    # canonical_drugs.name is trial-derived - assembled from sponsor-typed intervention
    # strings - and that is exactly where source misspellings enter: "bromocriptin"
    # (uncurated, prominence 1) sits next to "bromocriptine" (INN, prominence 23). Weighting
    # rather than dropping matters because 23,457 of 37,393 single-token drug terms are
    # uncurated; excluding them would cost far more coverage than the typos are worth, and
    # coverage is already this pack's weaker half. Down-weighted terms stay recognised by
    # correct? while falling below frequency_threshold as correction TARGETS - which is the
    # distinction spellkit actually draws.
    def score(prominence, curated)
      base = @floor + prominence
      return base if curated

      [(base * @uncurated_weight).round, 1].max
    end

    def add_term(term, prominence, is_protected, curated)
      token = term.gsub(TRIM, "").strip
      unless acceptable?(token, CURATED)
        @stats[:rejected_curated] += 1
        return
      end

      @stats[:from_curated] += 1
      @stats[curated ? :curated_provenance : :uncurated_provenance] += 1
      (curated ? @curated_terms : @uncurated_terms) << token
      record(token, score(prominence, curated))
      @protected << token if is_protected
    end

    # A fragment carries only PART of its concept, so it must not inherit the concept's whole
    # weight. Without this, decomposing the MeSH root "pathological conditions, signs and
    # symptoms" (prominence 141,729 - a rollup over every descendant trial) made "signs" and
    # "symptoms" the two highest-frequency terms in the pack, outranking "neoplasms" and
    # turning category glue into the strongest correction attractors in the index. Spreading a
    # phrase's prominence across its parts keeps a head word that recurs across many phrases
    # (diabetes) high, while a generic part of one inflated rollup stays modest.
    def add_phrase(phrase, prominence, curated)
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
        weighted = score(prominence, curated)
        @fragment_score[token] = weighted if weighted > @fragment_score[token]
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

    # An uncurated term ONE EDIT from a curated one is a misspelling of it, not a new name.
    #
    # This is the only rule that can fix "shadowing", and shadowing needs its own remedy
    # because membership in the index is BINARY: spellkit never corrects a word it can find,
    # so down-weighting a typo does nothing - it has to leave the dictionary entirely.
    # Measured on the v10 export, 95 of the 126 shadowed pairs have an uncurated misspelling
    # (amoxycillin, anastrazole, azythromycin, bendamustin - all at frequency 1) each sitting
    # one edit from the curated spelling it was blocking.
    #
    # Restricting the rule to UNCURATED terms is what keeps it safe: a genuinely novel name
    # that RxNorm, INN or UNII vouches for is never touched, and an uncurated name that is not
    # near anything curated is kept, since novelty is not evidence of error.
    #
    # Distance-1 is tested by shared deletion variant (SymSpell's own trick): two strings are
    # within one edit iff they share a common 1-deletion, counting the identity.
    def drop_suspected_typos
      return unless @drop_near

      index = Set.new
      @curated_terms.each do |term|
        index << term
        deletions(term) { |variant| index << variant }
      end

      @uncurated_terms.each do |term|
        next if @curated_terms.include?(term)

        suspect = index.include?(term)
        deletions(term) { |variant| suspect ||= index.include?(variant) } unless suspect
        next unless suspect

        @frequencies.delete(term)
        @stats[:dropped_suspected_typo] += 1
      end
    end

    def deletions(term)
      term.length.times { |i| yield term[0...i] + term[(i + 1)..] }
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
