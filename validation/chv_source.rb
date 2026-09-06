# frozen_string_literal: true

module Validation
  # Turns UMLS MRCONSO.RRF into (misspelling, correct drug name) pairs.
  #
  # The join mirrors Substrate's own (ingest/chv/parser.rb and
  # transform/models/restricted/chv/silver_chv_misspelling.sql) so the two agree: MRCONSO
  # carries both the CHV consumer strings and the RXNORM atoms, and a CHV atom and an
  # RXNORM atom for the same concept share a CUI. No separate crosswalk is needed.
  #
  # Scope is drugs only, and that is a property of the join, not a filter: a CHV concept
  # with no RXNORM atom is a condition, symptom or procedure, and reaching those is a
  # different join path (CHV CUI -> MeSH/MONDO).
  #
  # Columns (pipe-delimited, no header):
  #   CUI|LAT|TS|LUI|STT|SUI|ISPREF|AUI|SAUI|SCUI|SDUI|SAB|TTY|CODE|STR|SRL|SUPPRESS|CVF
  module ChvSource
    CUI = 0
    SAB = 11
    TTY = 12
    CODE = 13
    STR = 14
    SUPPRESS = 16
    MIN_FIELDS = 17

    Result = Struct.new(:pairs, :chv_atoms, :rxnorm_concepts, :unmatched, :identical,
      keyword_init: true)

    module_function

    # Preference order for the one RxNorm atom that represents a concept: the ingredient
    # name beats a precise/multiple ingredient, which beats a brand name. Same ranking as
    # silver_chv_misspelling.sql's rxnorm_ranked CTE.
    def tty_rank(tty)
      case tty
      when "IN" then 0
      when "PIN", "MIN" then 1
      when "BN" then 2
      else 3
      end
    end

    def parse(path, progress: nil)
      chv = []
      rxnorm = {}
      lines = 0

      File.foreach(path) do |line|
        lines += 1
        progress&.call(lines)

        fields = line.split("|", -1)
        next if fields.length < MIN_FIELDS
        next if fields[SUPPRESS] == "Y"

        cui = fields[CUI].to_s.strip
        string = fields[STR].to_s.strip
        next if cui.empty? || string.empty?

        case fields[SAB]
        when "CHV"
          chv << [cui, string.downcase]
        when "RXNORM"
          rank = [tty_rank(fields[TTY]), fields[CODE].to_s]
          current = rxnorm[cui]
          # Array has no <, and these are [rank, code] tuples, so compare with <=>.
          rxnorm[cui] = [rank, string.downcase] if current.nil? || (rank <=> current[0]) == -1
        end
      end

      join(chv, rxnorm)
    end

    def join(chv, rxnorm)
      pairs = {}
      unmatched = 0
      identical = 0

      chv.each do |cui, misspelling|
        match = rxnorm[cui]
        if match.nil?
          unmatched += 1
          next
        end

        expected = match[1]
        # A CHV string identical to the RxNorm name is spelling agreement, not a typo.
        if misspelling == expected
          identical += 1
          next
        end

        # Deterministic winner per misspelling, so two runs over the same release agree.
        existing = pairs[misspelling]
        pairs[misspelling] = expected if existing.nil? || expected < existing
      end

      Result.new(pairs: pairs, chv_atoms: chv.length, rxnorm_concepts: rxnorm.length,
        unmatched: unmatched, identical: identical)
    end

    def write(result, path)
      FileUtils.mkdir_p(File.dirname(path))
      File.open(path, "w") do |out|
        out.puts "# CHV drug misspellings, built by bin/fetch_chv from UMLS MRCONSO."
        out.puts "# UMLS-licensed: use locally, never commit or redistribute. See corpus/README.md."
        result.pairs.keys.sort.each { |misspelling| out.puts "#{misspelling}\t#{result.pairs[misspelling]}" }
      end
      path
    end
  end
end
