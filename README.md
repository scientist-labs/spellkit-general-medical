# spellkit-general-medical

A biomedical dictionary pack for [spellkit](https://github.com/scientist-labs/spellkit):
drug, condition, gene and target vocabulary **merged with general English**, so one checker
understands both `acetaminophen` and `the`.

```ruby
# Gemfile
gem "spellkit"
gem "spellkit-general-medical"
```

```ruby
# config/initializers/spellkit.rb
SpellKit.enable_dictionary(:general_medical, lazy: true)

SpellKit.correct("acetaminphen")   # => "acetaminophen"
SpellKit.correct("flexerol")       # => "flexeril"
SpellKit.correct("the")            # => "the"      (ordinary English is left alone)
SpellKit.correct("CDK10")          # => "CDK10"    (protected, never altered)
```

The gem registers itself when it loads, so naming it in your Gemfile is the whole setup.
The data ships **inside the gem** — no network, no cache, works air-gapped and in CI.

| | |
|---|---|
| Dictionary terms | 206,496 |
| Protected terms | 90,829 |
| Packaged size | 1.26 MB |
| Tuned defaults | `edit_distance: 2`, `frequency_threshold: 1.0` |

## Read this if you load it from a Rails initializer

**An initializer runs in every process that boots the app** — web, `rails db:migrate`,
`rake`, `console`, sidecars — not just the one that searches. This pack at its default
tuning costs **~2.1 GB resident and ~5.5s** to index, and loading it eagerly has already
OOM-killed a memory-constrained migrate init container in production.

Pass `lazy: true`, and warm it explicitly where you *do* want it:

```ruby
# config/puma.rb
on_worker_boot { SpellKit.load_dictionary! }
```

`stats` and `healthcheck` deliberately don't trigger the load, so a liveness probe can't
build the index in the process `lazy` protects. Full details in
[spellkit's README](https://github.com/scientist-labs/spellkit#dictionary-packs).

## Memory: `edit_distance` is the big lever

| | RSS | load | recall | error |
|---|---|---|---|---|
| `edit_distance: 2` (default) | 2,076 MB | 5.5s | 89.3% | 10.7% |
| `edit_distance: 1` | **484 MB** | 1.0s | 72.3% | 7.9% |

SymSpell's deletion index grows steeply with distance. If you are memory-constrained,
this matters far more than lazy loading does:

```ruby
SpellKit.enable_dictionary(:general_medical, lazy: true, edit_distance: 1)
```

Note `edit_distance: 1` is *less* likely to corrupt a term — it trades recall, not safety.

## Is it any good?

Measured against a held-out corpus of real consumer misspellings (NLM's Consumer Health
Vocabulary), scored over the same denominator as a generic English spellchecker:

| | corrections | wrong | unchanged |
|---|---|---|---|
| generic English (en-80k) | 59 (9.0%) | 104 | 489 |
| **this pack** | **451 (69.2%)** | **63** | 138 |

403 misspellings are fixed only by this pack — brand names and newer drugs (`flexeril`,
`semaglutide`, `pembrolizumab`) that no general word list carries. It also rewrites
**0.0%** of the thousand commonest English words.

**Caveats, because the numbers flatter the pack by construction:**

- A corpus of *drug* misspellings will always favour a drug dictionary. What makes the
  result meaningful is the pairing with the 0.0% English-mangling figure — gain on domain
  input, no measured cost on general input.
- Tuning was measured on **drug** misspellings only; the same constants are applied to
  condition and gene vocabulary, for which no held-out corpus exists.
- ~9.7% of corrections are wrong. Many are genuine ambiguity between real alternate
  spellings (`bromocriptin` vs `bromocriptine`), but a wrong correction is still wrong.
  Raise `frequency_threshold` if your surface prefers silence.
- Not yet validated against real query traffic, which is the only distribution that
  ultimately matters.

## Data sources

Built from RxNorm and MeSH (public domain, NLM), Open Targets/Ensembl gene symbols (CC0),
and SymSpell's `en-80k` English frequency list (MIT, © Wolf Garbe; derived from Google
Books Ngram data, CC BY 3.0). See [ATTRIBUTION.md](ATTRIBUTION.md) for the full table and
the NLM disclaimer.

NLM's Consumer Health Vocabulary is **not** in this artifact — it ships only inside the
gated UMLS Metathesaurus release and may not be redistributed. It is used locally as the
held-out validation corpus; only the tuning constants and aggregate figures leave that
process.

## Rebuilding the pack

See [RELEASING.md](RELEASING.md). Requires Substrate warehouse access for the source
export and your own UMLS licence for the validation corpus.

## Development

```bash
bundle install
bundle exec rspec
bundle exec standardrb
```
