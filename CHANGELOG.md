# Changelog

## [Unreleased]

### Added
- `SpellKit.enable_dictionary(pack_or_options)` and `SpellKit.dictionary_checker`, added by
  reopening the `SpellKit` module — spellkit itself is unmodified.
- Versioned pack registry (`data/packs.yml`) with `:medical` and `:general_medical`
  registered. Neither has a published release yet; both raise `PackNotReleasedError`.
- Artifact fetcher with permanent caching under `~/.cache/spellkit-dictionaries`, redirect
  following, SHA-256 verification, and atomic writes so a failed download can never become a
  cache hit.
- Per-pack `edit_distance` / `frequency_threshold` defaults carried in the registry.
- `SpellKit::Dictionaries.clear_cache!`, `.pack_names`, `.pack`, `.cache_dir`.
