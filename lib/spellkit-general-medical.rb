# frozen_string_literal: true

require "spellkit"
require_relative "spellkit/general_medical/version"

# Registers the general_medical pack with SpellKit when this gem loads. Bundler requires
# the gem automatically, so a consumer only has to name it in their Gemfile:
#
#   gem "spellkit"
#   gem "spellkit-general-medical"
#
#   SpellKit.enable_dictionary(:general_medical, lazy: true)
#
# The defaults below are not guesses. They were measured against a held-out corpus of real
# consumer misspellings (NLM's Consumer Health Vocabulary), which is why they ship WITH the
# data rather than being left for each consumer to rediscover:
#
#   edit_distance 2, frequency_threshold 1  ->  89.3% recall, 10.7% error
#   edit_distance 1, frequency_threshold 1  ->  72.3% recall,  7.9% error
#
# edit_distance 2 is the default because recall is what a search box is for. It costs
# memory, and steeply: ~2.1 GB resident against ~484 MB at edit_distance 1, since
# SymSpell's deletion index grows sharply with distance. A memory-constrained consumer
# should override it:
#
#   SpellKit.enable_dictionary(:general_medical, lazy: true, edit_distance: 1)
SpellKit::Packs.register(
  :general_medical,
  dictionary: File.expand_path("../data/dictionary.tsv", __dir__),
  protected_path: File.expand_path("../data/protected.txt", __dir__),
  defaults: {edit_distance: 2, frequency_threshold: 1.0},
  summary: "Drug, condition, gene and target vocabulary merged with general English"
)
