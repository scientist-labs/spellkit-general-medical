# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# spellkit ships a native Rust extension. During development, prefer a sibling
# checkout if one is present (the usual scientist-labs layout) so this gem can be
# exercised against unreleased spellkit changes; otherwise fall back to the
# published gem, which the gemspec already requires.
sibling = File.expand_path("../spellkit", __dir__)
gem "spellkit", path: sibling if File.directory?(sibling)
