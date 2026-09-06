# spellkit-dictionaries

Domain dictionary packs for [spellkit](https://github.com/scientist-labs/spellkit).

spellkit is a fast SymSpell typo corrector, and it deliberately ships no dictionaries. This
gem is the other half: a versioned registry of domain vocabularies, fetched and cached on
demand, so `SpellKit.correct("acetaminphen")` resolves to `"acetaminophen"` instead of the
nearest common English word.

```ruby
# Gemfile
gem "spellkit"
gem "spellkit-dictionaries"
```

```ruby
# config/initializers/spellkit.rb
SpellKit.enable_dictionary(:medical)

SpellKit.correct("acetaminphen")  # => "acetaminophen"
SpellKit.correct("CDK10")         # => "CDK10"  (protected, never "corrected")
```

## Pack catalog

| Pack | Contents | Latest |
|---|---|---|
| `:medical` | Drug, condition, gene and target names. Domain terms only — no general English. | *unreleased* |
| `:general_medical` | The medical pack merged onto spellkit's English word list, so one checker understands both. | *unreleased* |

Both packs are registered and named but **not yet published**. Calling
`SpellKit.enable_dictionary(:medical)` today raises `PackNotReleasedError` with a pointer
here, rather than failing with a 404. See [PLAN.md](PLAN.md) for what still has to land.

## How it works

This gem is a plugin. It **reopens the `SpellKit` module from the outside** to add
`enable_dictionary`, the same pattern countless gems use to extend a host library's
namespace. spellkit's own repo, gemspec and release cadence never change, and spellkit
never learns that "medical" is a thing. The dependency only points one way.

No dictionary data ships in this gem — only pointers. `data/packs.yml` maps a pack name to
its published release assets, and the multi-MB `.tsv` / `.txt` payloads are downloaded on
first use and cached under `~/.cache/spellkit-dictionaries/<pack>/<tag>/`.

### Why the registry ships inside the gem

spellkit's downloader caches by `SHA256(url)` with no TTL, no ETag and no revalidation.
A stable `releases/latest/download/...` URL would therefore pin every consumer to whatever
snapshot they happened to download first — permanently. So every URL in the registry is an
**immutable, version-tagged release asset**, which makes a new pack version a new URL, a new
cache key, and an actual refresh. Bumping `spellkit-dictionaries` is how you pick up a newer
pack. A spec enforces that no registered URL is a floating alias.

### Why this gem downloads, when spellkit already can

spellkit URL-downloads the `dictionary:` argument, but `protected_path:` goes straight
through to the Rust core as a filesystem path. A pack is a *pair* of files, so the protected
half has to be fetched here regardless. Fetching both halves together keeps a pack's two
files in one cache directory, under one tag, checksum-verified the same way.

## API

```ruby
# A pack, with its own validated tuning
SpellKit.enable_dictionary(:medical)

# Override anything spellkit's load! accepts
SpellKit.enable_dictionary(:medical, edit_distance: 2)

# Your own files - the registry is not consulted at all
SpellKit.enable_dictionary(dictionary: "path/to/mine.tsv", protected_path: "path/to/mine.txt")
```

`enable_dictionary` configures the **default** checker. To run more than one domain at once,
build independent checkers — spellkit's existing multi-instance API, with the pack lookup
done for you:

```ruby
medical = SpellKit.dictionary_checker(:medical)
legal   = SpellKit.dictionary_checker(dictionary: "legal.tsv")

medical.correct("acetaminphen")   # => "acetaminophen"
```

Introspection and cache management:

```ruby
SpellKit::Dictionaries.pack_names           # => [:medical, :general_medical]
SpellKit::Dictionaries.pack(:medical).summary
SpellKit::Dictionaries.pack(:medical).released?
SpellKit.dictionary_pack                    # pack backing the default checker, or nil

SpellKit::Dictionaries.cache_dir            # ~/.cache/spellkit-dictionaries
SpellKit::Dictionaries.clear_cache!(:medical)
SpellKit::Dictionaries.clear_cache!
```

Set `SPELLKIT_DICTIONARIES_CACHE_DIR` to relocate the cache (useful in a container with a
read-only home, or to bake packs into an image at build time).

### Pack defaults

`edit_distance` and `frequency_threshold` are tuned per pack against a held-out corpus of
real misspellings, and those values ship **with the pack pointer** rather than being left for
each consumer to rediscover. Anything you pass to `enable_dictionary` wins over them.

### Errors

All rooted at `SpellKit::Error`, so an existing `rescue SpellKit::Error` keeps working when
you switch from a hand-copied URL to a pack name.

| Error | Raised when |
|---|---|
| `Dictionaries::UnknownPackError` | The pack name is not in this gem version's registry |
| `Dictionaries::PackNotReleasedError` | The pack is registered but has no published release yet |
| `Dictionaries::RegistryError` | `data/packs.yml` is missing, unparseable, or a newer schema |
| `Dictionaries::DownloadError` | The artifact could not be fetched |
| `Dictionaries::ChecksumError` | A downloaded artifact did not match its registered `sha256` |

## Licensing

The MIT license in this repository covers the **code**. Pack artifacts are published as
GitHub Release assets and carry their own upstream source licenses and attribution
requirements; each release documents them.

One constraint is worth stating up front because it shapes the medical pack: NLM's Consumer
Health Vocabulary ships only inside the gated UMLS Metathesaurus release, so CHV-derived rows
are **never published in a pack artifact**. CHV is used only as a held-out validation corpus
for tuning `edit_distance` and `frequency_threshold`.

## Development

```bash
bundle install
bundle exec rspec
bundle exec standardrb
```

The specs run against the real spellkit native extension. If a sibling `../spellkit`
checkout exists, the Gemfile prefers it over the published gem.
