# frozen_string_literal: true

RSpec.describe SpellKit::Dictionaries::Fetcher do
  subject(:fetcher) { described_class.new }

  let(:url) { "https://example.test/releases/download/demo-v1/dictionary.tsv" }
  let(:sha) { Digest::SHA256.hexdigest(fixture_body("dictionary.tsv")) }
  let(:asset) { SpellKit::Dictionaries::Asset.new(url: url, sha256: sha) }
  let(:cache_key) { "demo/demo-v1/dictionary.tsv" }

  def fetch(with = asset)
    fetcher.fetch(with, cache_key: cache_key)
  end

  it "downloads an artifact and returns its cached path" do
    stub_request(:get, url).to_return(status: 200, body: fixture_body("dictionary.tsv"))

    path = fetch

    expect(File.read(path)).to eq(fixture_body("dictionary.tsv"))
    expect(path).to start_with(SpellKit::Dictionaries.cache_dir)
  end

  it "serves a second fetch from cache without a second request" do
    stub_request(:get, url).to_return(status: 200, body: fixture_body("dictionary.tsv"))

    fetch
    fetch

    expect(a_request(:get, url)).to have_been_made.once
  end

  it "follows redirects, as a GitHub release asset requires" do
    stub_request(:get, url)
      .to_return(status: 302, headers: {"Location" => "https://objects.example.test/signed/dictionary.tsv"})
    stub_request(:get, "https://objects.example.test/signed/dictionary.tsv")
      .to_return(status: 200, body: fixture_body("dictionary.tsv"))

    expect(File.read(fetch)).to eq(fixture_body("dictionary.tsv"))
  end

  it "resolves a relative Location against the url it just requested" do
    stub_request(:get, url)
      .to_return(status: 302, headers: {"Location" => "/signed/dictionary.tsv"})
    stub_request(:get, "https://example.test/signed/dictionary.tsv")
      .to_return(status: 200, body: fixture_body("dictionary.tsv"))

    expect(File.read(fetch)).to eq(fixture_body("dictionary.tsv"))
  end

  it "gives up rather than following a redirect loop" do
    stub_request(:get, url).to_return(status: 302, headers: {"Location" => url})

    expect { fetch }.to raise_error(SpellKit::Dictionaries::DownloadError, /Too many redirects/)
  end

  describe "checksum verification" do
    it "rejects a body that does not match the registered sha256" do
      stub_request(:get, url).to_return(status: 200, body: "tampered\t1\n")

      expect { fetch }.to raise_error(SpellKit::Dictionaries::ChecksumError, /Checksum mismatch/)
    end

    it "leaves nothing behind in the cache when a checksum fails" do
      stub_request(:get, url).to_return(status: 200, body: "tampered\t1\n")

      expect { fetch }.to raise_error(SpellKit::Dictionaries::ChecksumError)

      cached = File.join(SpellKit::Dictionaries.cache_dir, cache_key)
      expect(Dir.glob("#{File.dirname(cached)}/*")).to be_empty
    end

    it "accepts an asset with no registered checksum" do
      stub_request(:get, url).to_return(status: 200, body: fixture_body("dictionary.tsv"))

      path = fetch(SpellKit::Dictionaries::Asset.new(url: url))

      expect(File.read(path)).to eq(fixture_body("dictionary.tsv"))
    end
  end

  describe "failures" do
    it "explains a 404 in terms of the registry, not the network" do
      stub_request(:get, url).to_return(status: 404)

      expect { fetch }.to raise_error(SpellKit::Dictionaries::DownloadError, /404.*registry/m)
    end

    it "reports a server error with its status" do
      stub_request(:get, url).to_return(status: 500, body: "boom")

      expect { fetch }.to raise_error(SpellKit::Dictionaries::DownloadError, /500/)
    end

    it "rejects a non-http url" do
      asset = SpellKit::Dictionaries::Asset.new(url: "ftp://example.test/dictionary.tsv")

      expect { fetch(asset) }.to raise_error(SpellKit::Dictionaries::DownloadError, /must be http or https/)
    end
  end

  describe SpellKit::Dictionaries::Asset do
    it "derives a readable cache filename from the url path" do
      expect(described_class.new(url: url).filename).to eq("dictionary.tsv")
    end

    it "refuses an asset with no url" do
      expect { described_class.new(url: nil) }
        .to raise_error(SpellKit::Dictionaries::RegistryError, /missing a url/)
    end
  end
end
