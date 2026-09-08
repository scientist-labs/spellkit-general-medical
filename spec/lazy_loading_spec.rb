# frozen_string_literal: true

RSpec.describe "lazy dictionary loading" do
  before { use_registry("packs_released.yml") }

  after { SpellKit.default = nil }

  def lazy_options
    {dictionary: fixture("dictionary.tsv"), protected_path: fixture("protected.txt")}
  end

  describe "deferral" do
    it "registers without building an index" do
      SpellKit.enable_dictionary(lazy: true, **lazy_options)

      expect(SpellKit.dictionary_loaded?).to be false
    end

    it "does not fetch the pack artifacts either" do
      # Deferring only the index build would still leave a migrate container doing HTTP
      # at boot. Nothing is stubbed here, so any fetch attempt would raise under WebMock.
      expect { SpellKit.enable_dictionary(:demo, lazy: true) }.not_to raise_error
      expect(a_request(:get, %r{demo-v1})).not_to have_been_made
    end

    it "still validates the pack name at boot, where a typo is cheap to notice" do
      expect { SpellKit.enable_dictionary(:nonexistent, lazy: true) }
        .to raise_error(SpellKit::Dictionaries::UnknownPackError)
    end

    it "still refuses an unreleased pack at boot" do
      expect { SpellKit.enable_dictionary(:unreleased, lazy: true) }
        .to raise_error(SpellKit::Dictionaries::PackNotReleasedError)
    end
  end

  describe "what does and does not trigger the load" do
    before { SpellKit.enable_dictionary(lazy: true, **lazy_options) }

    it "loads on a real lookup" do
      expect(SpellKit.correct("flexerol")).to eq("flexeril")
      expect(SpellKit.dictionary_loaded?).to be true
    end

    it "does NOT load on stats" do
      # A liveness probe hitting a health endpoint must not materialise the index in the
      # very process this feature exists to protect.
      expect(SpellKit.stats).to include("deferred" => true, "loaded" => false)
      expect(SpellKit.dictionary_loaded?).to be false
    end

    it "does NOT load on healthcheck" do
      expect(SpellKit.healthcheck).to include("deferred" => true)
      expect(SpellKit.dictionary_loaded?).to be false
    end

    it "reports real stats once loaded" do
      SpellKit.correct("flexerol")

      expect(SpellKit.stats["loaded"]).to be true
    end
  end

  describe "explicit warm-up" do
    it "loads on demand, for a web-server boot hook" do
      SpellKit.enable_dictionary(lazy: true, **lazy_options)

      SpellKit.load_dictionary!

      expect(SpellKit.dictionary_loaded?).to be true
    end

    it "is a harmless no-op when the checker was loaded eagerly" do
      SpellKit.enable_dictionary(**lazy_options)

      expect { SpellKit.load_dictionary! }.not_to raise_error
      expect(SpellKit.dictionary_loaded?).to be true
    end
  end

  describe "thread safety" do
    it "builds the index at most once under concurrent first use" do
      # Without the mutex, two simultaneous first requests each build a multi-gigabyte
      # index. Count the builds rather than trusting the lock by inspection.
      builds = 0
      counter = Mutex.new
      allow(SpellKit::Dictionaries).to receive(:load_options).and_wrap_original do |original, *args, **kwargs|
        counter.synchronize { builds += 1 }
        original.call(*args, **kwargs)
      end

      SpellKit.enable_dictionary(lazy: true, **lazy_options)
      threads = 8.times.map { Thread.new { SpellKit.correct("flexerol") } }
      threads.each(&:join)

      expect(builds).to eq(1)
    end
  end

  describe "backwards compatibility" do
    it "still loads eagerly by default, so existing callers are unaffected" do
      SpellKit.enable_dictionary(**lazy_options)

      expect(SpellKit.dictionary_loaded?).to be true
    end

    it "reports not-loaded when nothing has been configured at all" do
      SpellKit.default = nil

      expect(SpellKit.dictionary_loaded?).to be false
    end
  end

  describe "independent lazy checkers" do
    it "defers a dictionary_checker too, without touching the default" do
      checker = SpellKit.dictionary_checker(lazy: true, **lazy_options)

      expect(checker.loaded?).to be false
      expect(checker.correct("flexerol")).to eq("flexeril")
      expect(checker.loaded?).to be true
    end
  end
end
