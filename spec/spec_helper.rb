# frozen_string_literal: true

require "spellkit-general-medical"
require "tmpdir"
require "tempfile"

module SpecHelpers
  FIXTURES = File.expand_path("fixtures", __dir__)

  def fixture(name)
    File.join(FIXTURES, name)
  end
end

RSpec.configure do |config|
  config.include SpecHelpers

  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.disable_monkey_patching!
  config.order = :random

  config.after { SpellKit.default = nil }
end
