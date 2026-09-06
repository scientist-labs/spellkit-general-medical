# frozen_string_literal: true

require "spellkit-dictionaries"
require "webmock/rspec"
require "tmpdir"
require "tempfile"
require "fileutils"

module PackSpecHelpers
  FIXTURES = File.expand_path("fixtures", __dir__)

  def fixture(name)
    File.join(FIXTURES, name)
  end

  def fixture_body(name)
    File.binread(fixture(name))
  end

  # Point the registry at a fixture catalog for the duration of an example.
  def use_registry(name)
    stub_const("SpellKit::Dictionaries::Registry::PATH", fixture(name))
    SpellKit::Dictionaries::Registry.reload!
  end

  # Serve the `demo` pack's two artifacts from its registered URLs.
  def stub_demo_pack
    stub_request(:get, "https://example.test/releases/download/demo-v1/dictionary.tsv")
      .to_return(status: 200, body: fixture_body("dictionary.tsv"))
    stub_request(:get, "https://example.test/releases/download/demo-v1/protected.txt")
      .to_return(status: 200, body: fixture_body("protected.txt"))
  end
end

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.disable_monkey_patching!
  config.order = :random

  config.include PackSpecHelpers

  config.around do |example|
    Dir.mktmpdir("spellkit-dictionaries-spec") do |dir|
      original = ENV[SpellKit::Dictionaries::ENV_CACHE_DIR]
      ENV[SpellKit::Dictionaries::ENV_CACHE_DIR] = dir
      begin
        example.run
      ensure
        ENV[SpellKit::Dictionaries::ENV_CACHE_DIR] = original
      end
    end
  end

  # The registry memoizes, and examples swap PATH out from under it.
  config.after { SpellKit::Dictionaries::Registry.reload! }
end
