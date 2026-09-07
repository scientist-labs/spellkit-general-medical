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
- Validation tooling (`validation/`, `bin/fetch_chv`, `bin/validate`) that tunes a pack's
  `edit_distance` / `frequency_threshold` against a held-out corpus of real misspellings,
  sweeping the grid and maximizing recall subject to an error-rate ceiling. Excluded from
  the packaged gem.
- False-positive measurement in `bin/validate`: the share of correctly-spelled common English
  a pack rewrites. Added after the medical pack was found rewriting 87.5% of the top 1,000
  English words while scoring 89% recall — a corpus of known misspellings cannot surface that.
- `bin/build_pack` + `pipeline/`: reshapes Substrate's dictionary-source export into
  spellkit's `dictionary.tsv` / `protected.txt` contract. Decomposes multi-word rows (SymSpell
  is a unigram index), spreads a phrase's prominence across its parts, filters English glue via
  spellkit's own frequency list, and requires a fragment to appear in 2+ phrases so source
  typos do not earn dictionary entries. Excluded from the packaged gem.
- `bin/fetch_chv` builds that corpus from UMLS MRCONSO with the operator's own
  `UMLS_API_KEY`, reproducing Substrate's CHV/RxNorm CUI join. The corpus is gitignored:
  UMLS-licensed content may be used locally but not redistributed.
