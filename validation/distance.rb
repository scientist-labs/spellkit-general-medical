# frozen_string_literal: true

module Validation
  # Levenshtein distance, bounded: anything past `max` is reported as max + 1 rather than
  # computed exactly, since the only question asked of it is "is this reachable within
  # spellkit's edit_distance?".
  module Distance
    module_function

    def between(a, b, max: 3)
      return 0 if a == b

      # A length gap alone can exceed the bound.
      return max + 1 if (a.length - b.length).abs > max

      previous = (0..b.length).to_a

      a.each_char.with_index do |char_a, i|
        current = [i + 1]

        b.each_char.with_index do |char_b, j|
          cost = (char_a == char_b) ? 0 : 1
          current << [
            previous[j + 1] + 1,  # deletion
            current[j] + 1,       # insertion
            previous[j] + cost    # substitution
          ].min
        end

        # Every remaining row can only grow the running minimum, so a whole row past the
        # bound means the final distance is past it too.
        return max + 1 if current.min > max

        previous = current
      end

      (previous.last > max) ? max + 1 : previous.last
    end
  end
end
