# frozen_string_literal: true

module SpellKit
  module Dictionaries
    # Rooted at SpellKit::Error so a consumer's existing `rescue SpellKit::Error`
    # keeps working when they switch from a hand-copied URL to a pack name.
    class Error < SpellKit::Error; end

    # A pack name that is not in the registry shipped with this gem version.
    class UnknownPackError < Error; end

    # A pack that exists in the registry but has no published artifacts yet.
    class PackNotReleasedError < Error; end

    # The registry file is missing, unparseable, or a schema version this gem
    # does not understand.
    class RegistryError < Error; end

    class DownloadError < Error; end

    class ChecksumError < Error; end
  end
end
