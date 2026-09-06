# frozen_string_literal: true

# Reopens SpellKit to add the pack-aware entry points. This is the whole plugin seam:
# spellkit is not modified, patched or wrapped - its namespace is simply extended from
# the outside, the same way many gems reopen a host library's module.
#
# Both methods end by calling spellkit's own public load! API, so spellkit keeps doing
# all the actual loading, indexing and hot-reload work exactly as it does today.
module SpellKit
  class << self
    # Configures the DEFAULT checker from a pack, so plain SpellKit.correct("...")
    # becomes domain-aware.
    #
    #   SpellKit.enable_dictionary(:medical)
    #   SpellKit.enable_dictionary(:medical, edit_distance: 2)
    #   SpellKit.enable_dictionary(dictionary: "my.tsv", protected_path: "my.txt")
    #
    # Any keyword spellkit's load! accepts may be passed and wins over the pack's own
    # tuned defaults. Returns the configured checker.
    def enable_dictionary(pack = nil, **options)
      checker = load!(**Dictionaries.load_options(pack, **options))
      @dictionary_pack = pack.nil? ? nil : Dictionaries.pack(pack)
      checker
    end

    # Builds an INDEPENDENT checker from a pack, for running more than one domain at
    # once. This is spellkit's existing multi-instance API with the pack lookup done
    # for you; it does not touch the default checker.
    #
    #   medical = SpellKit.dictionary_checker(:medical)
    #   medical.correct("acetaminphen")
    def dictionary_checker(pack = nil, **options)
      Checker.new.load!(**Dictionaries.load_options(pack, **options))
    end

    # The pack backing the default checker, or nil if it was configured some other way.
    # Useful in a healthcheck or boot log.
    attr_reader :dictionary_pack
  end
end
