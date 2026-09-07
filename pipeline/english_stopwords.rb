# frozen_string_literal: true

require "net/http"
require "uri"
require "fileutils"

module Pipeline
  # The most frequent English words, used to keep ordinary glue out of the pack.
  #
  # Only PHRASE-DERIVED tokens are filtered by this. Decomposing "ribosomal protein small
  # subunit" yields real vocabulary ("ribosomal") next to pure glue ("small"), and document
  # frequency cannot separate them: "pseudogene" occurs 16,210 times in the source and is
  # entirely legitimate, while "and" occurs 10,403 times and is not. What separates them is
  # that one is a common English word and the other is not.
  #
  # The list is spellkit's own default dictionary, so the general_medical pack's English half
  # and this filter agree by construction.
  module EnglishStopwords
    URL = "https://raw.githubusercontent.com/wolfgarbe/SymSpell/master/SymSpell.FrequencyDictionary/en-80k.txt"
    CACHE = File.expand_path("../tmp/en-80k.txt", __dir__)

    module_function

    # The list is sorted by frequency descending, so "top n" is just the first n lines.
    # Default 1000 is deliberately shallow: go much deeper and real clinical vocabulary
    # (cell, blood, heart, skin) starts being excluded as "common English".
    def top(count = 1000, path: CACHE)
      download(path) unless File.exist?(path)

      words = []
      File.foreach(path) do |line|
        word = line.split(/\s+/).first
        next if word.nil? || word.empty?

        words << word.downcase
        break if words.size >= count
      end
      words.to_set
    end

    def download(path)
      FileUtils.mkdir_p(File.dirname(path))
      warn "Downloading English frequency list..."
      uri = URI.parse(URL)
      body = Net::HTTP.get_response(uri).tap do |response|
        raise "Failed to fetch #{URL}: #{response.code}" unless response.is_a?(Net::HTTPSuccess)
      end.body
      File.write(path, body)
    end
  end
end
