# frozen_string_literal: true

require "uri"
require "net/http"
require "openssl"
require "fileutils"
require "digest"

module SpellKit
  module Dictionaries
    # Downloads pack artifacts and caches them on disk.
    #
    # spellkit can already download a `dictionary:` URL itself, but it cannot download a
    # `protected_path:` - that argument goes straight through to the Rust core as a
    # filesystem path (ext/spellkit/src/lib.rs). A pack is a PAIR of files, so this gem
    # needs its own fetcher to get the protected-terms half onto disk. Fetching both
    # halves here (rather than fetching one and delegating the other) keeps a pack's two
    # files in one cache directory, under one tag, verified the same way.
    #
    # Caching is permanent by design: every registry URL is an immutable version-tagged
    # release asset, so a cache hit can never be stale. A new pack version is a new URL
    # and therefore a new cache path.
    class Fetcher
      REDIRECT_LIMIT = 5

      attr_reader :cache_dir

      def initialize(cache_dir: nil, open_timeout: 10, read_timeout: 60)
        @cache_dir = cache_dir || Dictionaries.cache_dir
        @open_timeout = open_timeout
        @read_timeout = read_timeout
      end

      # Returns the local path to the cached artifact, downloading it if absent.
      def fetch(asset, cache_key:)
        path = File.join(cache_dir, cache_key)
        return path if File.exist?(path)

        FileUtils.mkdir_p(File.dirname(path))
        download(asset, path)
        path
      end

      private

      # Downloads to a scratch file and renames into place only after the checksum
      # passes, so an interrupted or corrupt transfer can never become a cache hit.
      def download(asset, path)
        scratch = "#{path}.download-#{Process.pid}-#{object_id}"

        begin
          digest = stream(asset.url, scratch)

          if asset.sha256 && digest != asset.sha256
            raise ChecksumError,
              "Checksum mismatch for #{asset.url}\n  expected sha256 #{asset.sha256}\n  " \
              "got      sha256 #{digest}\nThe download was discarded."
          end

          File.rename(scratch, path)
        ensure
          FileUtils.rm_f(scratch)
        end
      end

      def stream(url, destination, redirects_left: REDIRECT_LIMIT)
        uri = parse(url)
        digest = Digest::SHA256.new

        Net::HTTP.start(uri.host, uri.port,
          use_ssl: uri.scheme == "https",
          open_timeout: @open_timeout,
          read_timeout: @read_timeout,
          verify_mode: OpenSSL::SSL::VERIFY_PEER) do |http|
          http.request(Net::HTTP::Get.new(uri.request_uri)) do |response|
            case response
            when Net::HTTPRedirection
              return follow(url, response, destination, redirects_left)
            when Net::HTTPSuccess
              File.open(destination, "wb") do |file|
                response.read_body do |chunk|
                  digest << chunk
                  file.write(chunk)
                end
              end
            when Net::HTTPNotFound
              raise DownloadError,
                "Pack artifact not found (404): #{url}. The registry in this version of " \
                "spellkit-dictionaries may point at a release that was removed or renamed."
            else
              raise DownloadError, "Failed to download #{url}: #{response.code} #{response.message}"
            end
          end
        end

        digest.hexdigest
      rescue Timeout::Error => e
        raise DownloadError, "Timed out downloading #{url}: #{e.message}"
      rescue SystemCallError, OpenSSL::SSL::SSLError, Net::HTTPBadResponse, IOError => e
        raise DownloadError, "Failed to download #{url}: #{e.message}"
      end

      def follow(url, response, destination, redirects_left)
        raise DownloadError, "Too many redirects downloading #{url} (limit #{REDIRECT_LIMIT})" if redirects_left <= 0

        location = response["location"]
        raise DownloadError, "Redirect from #{url} carried no Location header" if location.nil? || location.empty?

        # GitHub release assets redirect to a signed object-store URL, and the Location
        # is allowed to be relative, so resolve it against the URL we just requested.
        stream(URI.join(url, location).to_s, destination, redirects_left: redirects_left - 1)
      end

      def parse(url)
        uri = URI.parse(url)
        unless uri.is_a?(URI::HTTP) && uri.host
          raise DownloadError, "Pack artifact URL must be http or https, got: #{url}"
        end

        uri
      rescue URI::InvalidURIError => e
        raise DownloadError, "Invalid pack artifact URL #{url.inspect}: #{e.message}"
      end
    end
  end
end
