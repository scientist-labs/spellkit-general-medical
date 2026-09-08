# frozen_string_literal: true

module SpellKit
  module GeneralMedical
    VERSION = "1.0.0"

    # Terms in data/dictionary.tsv, for a boot log or a healthcheck.
    TERM_COUNT = 206_496

    # Terms in data/protected.txt - gene/target symbols and alphanumeric designations
    # that must never be "corrected" into an English word.
    PROTECTED_COUNT = 90_829
  end
end
