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
SpellKit.enable_dictionary(:general_medical)   # <- the one you almost certainly want

SpellKit.correct("acetaminphen")  # => "acetaminophen"
SpellKit.correct("CDK10")         # => "CDK10"  (protected, never "corrected")
```

## Pack catalog

| Pack | Contents | Latest |
|---|---|---|
| `:general_medical` | Medical terms **plus** general English. **Start here.** | *built, unreleased* |
| `:medical` | Domain terms only. Safe only if every token you pass is already known to be a domain term — see below. | *built, unreleased* |

> **`:medical` alone will corrupt ordinary text.** Measured on the v10 build, it rewrites
> **87.5%** of the thousand commonest English words — `the` → `dhe`, `and` → `aid`,
> `with` → `witch` — because a dictionary containing no English treats every ordinary word as
> an unknown to be corrected. That is inherent to any domain-only dictionary, not a defect in
> this build. `:general_medical` scores **0.0%** on the same probe while fixing more drug
> typos. Reach for `:medical` only when you are filtering tokens yourself.

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

## Building a pack

```bash
# 1. In the substrate repo, export the name surface (read-only, production v10)
bin/export_dictionary_source.rb --output dict_source.tsv

# 2. Here, reshape it into spellkit's contract
bin/build_pack --source dict_source.tsv --out build/medical
```

`bin/build_pack` does the SymSpell shaping the export deliberately leaves alone:

- **Decomposes phrases.** SymSpell is a unigram index, so a multi-word row can never match a
  typed token — and on the real v10 export 162,605 of 275,936 rows are phrases. This is not
  merely wasteful: `diabetes` occurs *only* inside phrases, so without decomposition "diabets"
  corrects to nothing.
- **Spreads a phrase's prominence across its parts.** Otherwise the MeSH root category
  "pathological conditions, signs and symptoms" makes `signs` and `symptoms` the two
  highest-frequency terms in the pack.
- **Filters English glue** from fragments using spellkit's own frequency list, so `ribosomal`
  survives decomposition and `small` does not.
- **Requires a fragment to appear in 2+ distinct phrases.** Substrate's drug names include
  sponsor-typed trial intervention names, so genuine typos are present in the source. Admitting
  one disables correction of that typo entirely, because spellkit never corrects a word it can
  find — `frequency_threshold` governs correction *targets*, not membership. The cost is that
  legitimately rare words appearing in a single phrase are dropped too; `--min-fragment-df 1`
  turns the rule off.
- **Scores `1 + prominence`, not a high floor.** A large floor makes every term look
  respectable and neuters `frequency_threshold`, which is the lever that keeps a low-signal
  term from winning a correction.

## Validation

`edit_distance` and `frequency_threshold` are not guesses — they are measured against a
held-out corpus of real misspellings and then published with the pack.

```bash
export UMLS_API_KEY=...
bin/fetch_chv                                          # build the corpus (one-time, several GB)
bin/validate --dictionary build/dictionary.tsv         # sweep the grid, get the two numbers
```

`bin/validate` scores every `(edit_distance, frequency_threshold)` pair and recommends the
one with the best recall whose error rate clears `--max-error-rate` (default 2%). Recall is
maximized *subject to* harm, never traded against it: in a search box a confident wrong
correction is worse than no correction.

Every corpus pair lands in exactly one bucket:

| Bucket | Meaning |
|---|---|
| `hit` | Corrected to the expected term |
| `wrong` | Corrected to a **different** term — the harmful case |
| `miss` | Left unchanged, no suggestion offered |
| `unreachable` | The correct term isn't in the dictionary, so no tuning could produce it |
| `shadowed` | The "misspelling" is itself a real term — correctly left alone |

`recall` and `error_rate` are both over `hit + wrong + miss`, so they stay comparable across
configs while dictionary coverage remains a separate number. The report also prints the share
of pairs sitting further than edit distance 2 from their target — the hard ceiling on recall
for *any* edit-distance corrector, and the number that decides whether a phonetic fallback in
spellkit's Rust core is worth proposing.

### The corpus is never committed

The corpus is built from NLM's Consumer Health Vocabulary: real misspellings people typed,
mapped to the concept they meant. CHV ships only inside the gated UMLS Metathesaurus release,
so a licence holder may **use** it here, but redistributing it — which committing it to a
public repo would do — is not permitted. `corpus/` is gitignored, and `bin/fetch_chv`
rebuilds it from your own UMLS key.

What leaves that directory is two numbers plus aggregate accuracy figures. Those are
measurements derived from the corpus, not the corpus itself. Row-level misspelling/term pairs
are never published, since that would reconstruct CHV.

To reproduce a pack's tuning you need your own [UMLS licence](https://uts.nlm.nih.gov/uts/signup-login).
See [corpus/README.md](corpus/README.md). The harness reads any two-column
`misspelling<TAB>correct term` TSV, so you can point `--corpus` at your own instead.

**Scope caveat**: CHV's drug coverage is what the join reaches, so constants tuned this way
are measured on *drug* misspellings and then applied to a pack that also holds conditions and
gene symbols. Release notes should say so rather than implying the whole pack was validated.

## Licensing

The MIT license in this repository covers the **code**. Pack artifacts are published as
GitHub Release assets and carry their own upstream source licenses and attribution
requirements; each release documents them.

One constraint is worth stating up front because it shapes the medical pack: NLM's Consumer
Health Vocabulary ships only inside the gated UMLS Metathesaurus release, so CHV-derived rows
are **never published in a pack artifact**, and the corpus built from it is never committed.
CHV is used only locally, as a held-out validation corpus — see [Validation](#validation).

## Development

```bash
bundle install
bundle exec rspec
bundle exec standardrb
```

The specs run against the real spellkit native extension. If a sibling `../spellkit`
checkout exists, the Gemfile prefers it over the published gem.

`validation/` and `bin/` are build-time tooling and are deliberately excluded from the
packaged gem — a consumer installs Ruby pointers, not a pipeline. The validation specs pin
the harness against small synthetic fixtures (hand-authored typos, no UMLS content), so they
run on a fresh clone; the specs that need the real corpus skip when it is absent.
