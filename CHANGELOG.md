# Changelog

## 1.0.0

First release as a standalone pack gem.

### Added
- The `general_medical` pack, registering itself with `SpellKit::Packs` on load: 206,496
  terms and 90,829 protected terms, vendored in the gem (1.26 MB packaged).
- Tuned defaults (`edit_distance: 2`, `frequency_threshold: 1.0`) shipped WITH the data,
  measured against a held-out corpus rather than left for each consumer to rediscover.

### Changed from spellkit-dictionaries
This gem replaces `spellkit-dictionaries`, which has been yanked.

- **The data ships in the gem instead of being fetched over HTTP.** The download bought
  nothing: the pack registry shipped inside a gem anyway, so a pack release already
  required a gem release. It cost a network dependency on the boot path, a cache
  directory, checksum machinery, and two failure modes consumers had to handle.
- **`enable_dictionary` and lazy loading moved into spellkit 1.0.0**, where they belong -
  spellkit now provides the pack mechanism and still bundles no dictionaries.
- **Packs are chosen in the Gemfile**, by naming the gem. Ruby has no feature-flag
  mechanism (that is Cargo); the gem is the unit of selection, and it buys independent
  version pinning per pack as a bonus.
- The domain-only `medical` pack is **not published**. Alone it rewrites 87.5% of the
  thousand commonest English words, because a dictionary containing no English treats
  every ordinary word as an unknown to correct.
