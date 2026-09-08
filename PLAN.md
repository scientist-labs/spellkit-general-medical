# spellkit-general-medical

> **STATUS, 2026-09-08.** This plan is kept as the design record; the shape it describes
> has since changed in three ways worth knowing before reading it.
>
> 1. **The registry moved into spellkit** (1.0.0). spellkit now ships the pack MECHANISM -
>    `SpellKit::Packs.register`, `enable_dictionary`, lazy loading - and still bundles no
>    dictionaries. A pack registers itself; spellkit knows the name of none.
> 2. **The data ships in this gem, not over HTTP.** The download design bought nothing:
>    the registry shipped inside a gem anyway, so a pack release already required a gem
>    release. It cost a network dependency on the boot path, a cache, checksum machinery
>    and two failure modes. Deleted.
> 3. **This repo is now one pack, not a multi-pack registry.** It was renamed from
>    `spellkit-dictionaries`, which is yanked. A second domain would be its own gem and
>    its own repo, chosen in the Gemfile by name - Ruby has no feature flags, so the gem
>    IS the unit of selection.
>
> The medical findings below - sources, licensing, frequency design, validation - all
> still hold and are why this file is kept rather than deleted.


Plan for a domain-dictionary pipeline that makes [spellkit](https://github.com/scientist-labs/spellkit)
typo-correction scientifically/medically aware. Written 2026-09-04.

## Why this repo and not a new spellchecker

The original ask was "build a scientifically-aware spellchecker, Magnus over a Rust library
instead of wrapping C." That library already exists: `spellkit` (scientist-labs/spellkit, MIT,
v0.2.0) is a Ruby gem over a hand-rolled Rust SymSpell implementation bound with Magnus
(`magnus = "0.7"`, `rb-sys`), with exactly the shape that was going to be proposed here (a Rust
SymSpell port over a generic C spellchecker). It already supports everything the "scientific"
half of this needs at the API level:

- a configurable per-instance dictionary (`term<TAB>frequency` TSV, from a file or URL)
- a protected-terms list (exact match + regex), so a real term never gets "corrected" into a
  common word
- multiple independent instances (so a `medical` checker and a general-English checker can
  coexist)
- hot reload, so a dictionary can be swapped without restarting the consuming app

What it does NOT have is a medical/scientific dictionary - its README literally shows a
`medical_checker` example loading `medical_dictionary.tsv` / `medical_terms.txt`, but neither
file exists anywhere; it's illustrative, not shipped. **The gap is data, not code.** This repo
closes that gap: it builds the dictionary and protected-terms artifacts spellkit already knows
how to consume, sourced from data Substrate already ingests (RxNorm, UNII, MONDO/MeSH, and soon
CHV). spellkit itself is not modified by this plan.

Non-goal: rewriting or extending spellkit's Rust core. If real-world typos turn out not to be
edit-distance-bounded (see "Open question: phonetic fallback" below), that is a separate proposal
against spellkit itself, not something this repo works around.

## What this repo produces

Two files per release, matching spellkit's existing `Dictionary Format` / `Configuration` (README
"Dictionary Format", "Configuration" sections):

1. **`dictionary.tsv`** - `term<TAB>frequency`, one row per drug/condition/gene/target name
   spellkit's SymSpell index should know about, so `SpellKit.correct("acetaminphen")` resolves to
   a real term instead of the nearest common English word.
2. **`protected.txt`** - exact-match terms (one per line) plus regex patterns, for names that must
   never be silently corrected away (gene symbols, alphanumeric brand codes, anything that looks
   like a typo of an English word but is a real scientific term - e.g. a checker should not
   "fix" a legitimately unusual-looking approved name).

Published as versioned, dated release artifacts (GitHub Release assets on this repo, mirroring
how spellkit's own README points at raw SymSpell dictionary URLs) so a consumer just points
`SpellKit.load!(dictionary: "https://github.com/scientist-labs/spellkit-dictionaries/releases/.../dictionary.tsv")`
at the latest tag. No runtime dependency on Substrate or its database - the pipeline is a
build-time job, the artifact is a static file pair.

## Packaging and distribution: one repo, many domain packs

Chris asked (2026-09-05): should domain dictionaries be modular and optionally includable - the
same repo eventually hosting a `medical` pack, a `finance` pack, a `legal` pack, any jargon-heavy
industry - and should that live inside spellkit itself, optionally?

**Decision: modular packs, one per domain, in this repo; spellkit's core stays pack-free.**

- **This repo becomes a multi-pack repo, not a medical-only one.** Rename the mental model (not
  necessarily the repo, "spellkit-dictionaries" already reads as the general home) from "the
  medical dictionary" to "a domain pack" with `medical` as the first one built. Each pack is an
  independent `dictionary.tsv` + `protected.txt` pair, its own build script/source-list, its own
  version/release tag (`medical-v1`, `medical-v2`, a future `finance-v1`, ...), and its own
  validation pass (a finance pack's held-out test corpus looks nothing like CHV). Packs do not
  share a release cadence - shipping `medical-v3` never forces a `finance` consumer to do anything.
- **spellkit's core gem stays exactly as small and dictionary-free as it is today.** Its own README
  is explicit that this is a deliberate design choice ("SpellKit doesn't bundle dictionaries"), and
  that's the right call to preserve: a finance-only consumer should not pay install size or load
  time for a medical vocabulary sitting unused in the gem, and vice versa. **Do not vendor pack
  data files into spellkit's gemspec.** This repo, not spellkit, owns the data payload.
- **REVISED 2026-09-06: zero changes to spellkit's own repo, not even a small PR.** The original
  plan here proposed a `SpellKit::Dictionaries` pointer constant added to spellkit itself. Better:
  `spellkit-dictionaries` ships as an actual small Ruby gem (not just a repo of release assets),
  and that gem **reopens the `SpellKit` module from the outside** to add the convenience API - the
  same standard Ruby plugin pattern countless gems use to extend a host library's namespace without
  the host needing to know the plugin exists (the way many gems reopen `ActiveRecord::Base`).
  spellkit's own repo/gemspec/release cadence never has to change, and never has to know "medical"
  is a thing. All domain-awareness lives in the new gem, which depends on spellkit, never the
  reverse.
- **The developer-facing API**, all provided by the `spellkit-dictionaries` gem:
  ```ruby
  # Gemfile
  gem "spellkit"
  gem "spellkit-dictionaries"

  # initializer
  SpellKit.enable_dictionary(:medical)          # domain-only pack
  SpellKit.enable_dictionary(:general_medical)  # medical terms merged onto spellkit's own
                                                 # English word list - see "Once the Substrate
                                                 # export exists" below, step 5
  SpellKit.enable_dictionary(:medical, edit_distance: 2)   # passes through any spellkit config
  SpellKit.enable_dictionary(dictionary: "path/to/mine.tsv",
                              protected_path: "path/to/mine.txt")  # fully custom, bypasses the
                                                                    # registry entirely
  ```
  `enable_dictionary` does two things: if given a known Symbol, resolves it via a small
  `{pack_name => {dictionary: url, protected: url}}` registry shipped and versioned WITH the gem
  (bumping the `spellkit-dictionaries` gem version is how a consumer picks up awareness of new
  packs/versions); if given a Hash/kwargs, passes straight through to spellkit's own `load!`/
  `configure`, unchanged. Either way it ends by calling spellkit's existing public config API - no
  new loading/caching/hot-reload mechanism, spellkit's own downloader and `~/.cache/spellkit/`
  caching still does all of that work exactly as it does today. The gem itself stays tiny (Ruby
  source only, no bundled data, matching spellkit's own "don't bundle dictionaries" rule) - the
  actual TSV/protected.txt files are still fetched over the network and cached at runtime, just
  addressed by name instead of a hand-copied URL. Power users who want more than one domain active
  at once still reach for spellkit's existing multi-instance API (`SpellKit::Checker.new`)
  underneath this exactly as they do today; `enable_dictionary` is sugar over the common
  single-pack case, not a replacement for it.
- **Discoverability**: this repo's README becomes a small catalog (pack name, one-line
  description, latest version, term count, what it's built from) once more than one pack exists.
  With only `medical` planned right now, that catalog is a placeholder of one row - real effort
  goes in only when a second pack is actually being built, not speculatively now.

### Internal plumbing vs. the public artifact - don't confuse the two

Chris asked (2026-09-06) why any of this needs to know about a database at all, given "no DB
credential in this repo, ever." Worth stating plainly since it's easy to conflate:

- **This repo's packaging/distribution mechanism has no inherent database dependency.** It is
  generically "host pre-built dictionary+protected-term file pairs, publish as versioned
  releases." A hypothetical `finance` pack would pull from wherever financial terminology lives,
  with zero Substrate involvement.
- **The `medical` pack specifically** needs medical vocabulary from somewhere, and Substrate is
  where Chris already has it, cleaned and cross-referenced. That is a fact about this one pack's
  data source, not a property of the repo or the gem.
- **The Substrate export (see "Data access: resolved" below) is internal plumbing only** - a flat
  file of raw names/frequency/protected-flag, consumed solely by this repo's own medical-pack
  build step. It is not documented, not stable API, not something a developer ever sees or should
  look for.
- **The only artifact "any developer" ever touches is this repo's own published release**
  (`dictionary.tsv` / `protected.txt`, fetched via `SpellKit.enable_dictionary`). Substrate is
  invisible past the build step that produces that file.

Non-goal for this pass: building a `finance` or `legal` pack. Nothing here is currently ingesting
finance/legal jargon, so there is no source data to build one from yet - the packaging shape above
just makes adding one later a matter of dropping in a new build script and a new release tag, not
a redesign.

## Data sources (all already ingested by Substrate, all public per docs/data-catalog.md)

| Source | Substrate model | What it contributes |
|---|---|---|
| RxNorm (ingredient/brand/synonym names) | `canonical_drug_rxnorm`, `canonical_drug_brand_rxnorm` | Correct generic + brand drug names (Flexeril, cyclobenzaprine, ...) |
| FDA UNII / GSRS | `silver_unii_names` (global substance match surface) | Substance names, including ex-US/investigational (broader than RxNorm's US-marketed scope) |
| NDC directory (openFDA) | `silver_drug_names` | Marketed generic/brand names actually dispensed in the US |
| MONDO / MeSH | canonical condition marts (`ingest/mondo`, `ingest/mesh` per data-catalog) | Correct disease/condition names |
| Gene/target symbols | canonical target marts | Correct gene/target symbols (also a natural `protected.txt` source - symbols like `CDK10` must never "correct" to a dictionary word) |
| **NLM Consumer Health Vocabulary (CHV)** | `restricted.restricted_drug_misspelling` (ingested; substrate PR #2767) | Real people's actual misspellings mapped to correct concepts. This is the one source in this table that is misspellings, not names - see below. **VALIDATION ONLY, never published - see "CHV cannot ship in a public artifact" below.** |

RxNorm/UNII/MONDO/MeSH give the correct-spelling side of the dictionary (the "what should this
typo resolve TO" half). CHV is the only source that captures actual observed typos (the "what do
real users actually type" half) - it's what turns a generic edit-distance corrector into one
tuned to real medical misspelling patterns rather than a blind Levenshtein sweep over a drug-name
word list. The dictionary itself is built from RxNorm/UNII/MONDO/MeSH; CHV's role is narrower
than an earlier draft of this plan assumed, and the reason is licensing.

### CHV cannot ship in a public artifact (finding, 2026-09-06)

An earlier revision of this plan proposed folding CHV in "both as dictionary input and as a
held-out test corpus". **The first half is not available to us.** Substrate's own
`docs/data-catalog.md` classifies CHV drug misspellings as tier **licensable**, tag
`restricted` from `silver_chv_misspelling` onward, and states the constraint plainly: unlike
RxNorm, which ships its own separate no-key Prescribable zip as a fallback, "CHV has NO
independent ungated NLM distribution and ships only inside the gated UMLS Metathesaurus full
release, so our commercial right to it depends entirely on continuing to hold that UMLS
license."

This repo's whole output is a *public* release asset downloaded by arbitrary third parties who
hold no UMLS license. Publishing CHV-derived rows in `dictionary.tsv` would be redistribution,
not use. So:

- **CHV is never a source of published terms.** Not in `dictionary.tsv`, not in `protected.txt`,
  not in the merged `general-medical` variant.
- **CHV as a held-out validation corpus is fine and stays**, because that is use, not
  redistribution: the misspelling pairs are read at build time to tune `edit_distance` and
  `frequency_threshold`, and only the resulting two tuned *numbers* are published. Those numbers
  ship in the pack registry (see "Packaging" above), not the artifact.
- The same test applies to every future source: **tier `none` may be published; tier
  `licensable` or `prohibited` may be measured against, never republished.** RxNorm
  (Prescribable), UNII/GSRS, openFDA NDC, MONDO and MeSH are all tier `none` per the same
  catalog, so the dictionary half is unaffected.
- **This constrains the Substrate export in step 3**: the export must not carry CHV-derived
  terms into the column this repo publishes. A misspelling/concept pair column for validation is
  fine, but it must be separable and clearly marked, and the build must fail closed if a
  validation-only column ever reaches the published artifact.

## Frequency: the part that needs real design

SymSpell needs a `frequency` per dictionary term - spellkit uses it both to rank multiple
candidate corrections and, via `frequency_threshold`, to refuse to "correct" a common word into a
rare one. Substrate's canonical vocab has no natural corpus-frequency the way a web-crawl word
list does. Options, roughly in order of first-pass preference:

1. **Prominence as a proxy.** `serving_search.prominence` (the field `ServingSearch#ranked`
   already orders by) is Substrate's existing "how busy/notable is this entity" signal across all
   eight searchable axes. Reuse it directly: a well-known drug outranks an obscure one as a
   correction target, which is the right default behavior for a search-typeahead use case.
2. **Real-world volume signals** where they exist and are unrestricted: NDC dispensing/NADAC
   volume for drugs, FAERS report counts, trial-arm mention counts. More authoritative than
   prominence but source-specific plumbing per entity type; second pass.
3. **Flat/tiered frequency** (e.g. IN > BN > SY, RxNorm TTY order Substrate's own
   `silver_rxnorm.sql` already ranks by) as a floor when no volume signal exists, so every real
   term still clears `frequency_threshold` and is reachable, even if ranking among candidates is
   coarse.

Start with (1), since it's a single already-computed column and covers all axes uniformly; layer
(2) in per-axis later if correction quality demands it.

## Update model: static artifact, rebuilt periodically, no live coupling

Chris asked (2026-09-06): is this a static list we update periodically, does it need a
downloader, does it pull from the client app where the gem is installed? Answering all three
plainly, since this shapes the whole design:

- **Static, not live.** `dictionary.tsv` / `protected.txt` are point-in-time build artifacts, not
  something spellkit queries at request time. A consuming app loads one at boot (or on hot-reload)
  and it stays fixed in memory until reloaded - no runtime dependency on Substrate, this repo, or
  the network on the request path.
- **Rebuilt periodically, not continuously.** This repo's pipeline reruns on a cadence (recommend
  monthly, matching RxNorm/CHV's own upstream monthly release rhythm - rebuilding weekly would just
  reprocess the same source data) and cuts a new versioned GitHub Release each time. That's a
  scheduled job in THIS repo (a GitHub Actions cron, or triggered by hand), separate from and
  unaware of any consuming app's deploy cycle.
- **CORRECTED 2026-09-06 (both halves of this bullet were wrong; see "Two corrections from
  reading spellkit's source" below).** A downloader IS needed, because spellkit will not fetch
  `protected_path`, only `dictionary`. And consumers must point at **pinned, version-tagged
  URLs**, not `releases/latest/download/...`, because spellkit's cache never revalidates - a
  floating URL pins a consumer to their first download permanently, which is the exact opposite
  of the freshness the alias was chosen for. Freshness comes from bumping the
  `spellkit-dictionaries` gem, whose registry carries the new tagged URL.
- **Not client-app-sourced.** The dictionary is NOT built from data living in whatever app installs
  the gem. It is built ONCE, centrally, from Substrate's canonical warehouse (the actual source of
  drug/condition/gene names), and every consumer - explore, or any other app that installs
  `spellkit` and points it at this repo's published URL - downloads the exact same shared artifact.
  A consuming app needs no database access, no build step, and no knowledge of Substrate at all;
  it just names a URL, identically to how it already points at `SpellKit::DEFAULT_DICTIONARY_URL`
  for general English today.

## Pipeline shape

Ruby, matching Substrate's own ingest-connector conventions (this repo reads Substrate's
canonical schema the same way any downstream consumer would - read-only, no gems beyond what's
needed, no Rails). Rough shape:

### Data access: resolved (2026-09-06)

**Decision: no direct DB credential in this repo, ever.** Substrate's own architecture already
draws this line consistently - `explore` itself only ever gets a least-privilege `explore_ro`
role, and `sdk/ruby` exists specifically so external consumers have a supported interface instead
of raw DB access. An external repo (this one, outside Substrate's trust boundary, on a different
org's CI) holding a warehouse credential - even read-only - would be a real departure from that
pattern, and a bigger blast-radius risk than anything this project needs to accept.

**Instead: a small export step lives IN Substrate, this repo only ever consumes its output.**

1. **Substrate side (new, small, in-repo)**: a script (e.g. `bin/export_dictionary_source.rb`, or
   a dedicated `serving`-layer dbt model + a thin export task - whichever matches how other
   one-off exports are already done here, check for precedent first) that runs with Substrate's
   own existing DB access (no new credential, no new trust boundary) and dumps exactly the columns
   this pipeline needs - term, frequency-proxy (`prominence`), a `protected` flag/reason for
   gene/target symbols and alphanumeric codes - to a flat file. Publish that file as a GitHub
   Release asset on the **substrate** repo (or push to S3 - whichever this project's existing
   export precedent uses), on a cadence (monthly, matching this project's own rebuild cadence) or
   on demand.
2. **This repo (spellkit-dictionaries) consumes that export**, not Substrate's database. Its own
   job shrinks to: pull the published Substrate export, reshape into spellkit's exact
   `dictionary.tsv` / `protected.txt` contract (lowercase, de-duplicate, sort by frequency
   descending), validate, and publish its own release. No DB credential, no API client, no network
   surface beyond downloading one file Substrate already made public to itself.
3. This also cleanly answers "does it pull from the client app" from a different angle: the data
   flow is Substrate (produces) -> this repo (reshapes and republishes) -> spellkit (loads) ->
   consuming app. The consuming app never touches Substrate or this repo's build step, only the
   final published dictionary URL - see "Update model" above.

**What this means for scope**: building this properly now needs a small Substrate-side ticket
(the export script) BEFORE this repo's own pipeline can be built for real. That ticket is
independent, low-risk (an export, not a schema/warehouse change), and unblocks this repo cleanly.
Until it exists, this repo cannot progress past this PLAN.

### Once the Substrate export exists, this repo's own steps are

1. Pull the published Substrate export.
2. Reshape: lowercase, de-duplicate, salt-normalize (the export can pre-normalize with the same
   `drug_key`/`name_key` macros Substrate already uses; simplest if that normalization happens on
   the Substrate side and this repo just trusts the export's key column).
3. Emit `dictionary.tsv` sorted by frequency descending (SymSpell convention).
4. Emit `protected.txt` from the export's protected flag/reason.
5. **Also emit a merged variant** (ergonomics, see below): `general-medical/dictionary.tsv` /
   `protected.txt`, the medical pack's terms unioned onto spellkit's own `DEFAULT_DICTIONARY_URL`
   English word list (frequencies from each source's own scale, medical terms getting a
   conservative floor so they don't drown out common English words or vice versa - needs empirical
   tuning once real data exists). This serves the developer who wants ONE checker instance that
   understands both plain English and drug names, without managing two `SpellKit::Checker`
   instances themselves. Ship `medical/` (domain-only) and `general-medical/` (merged) as two
   pack variants from day one, since the merge logic is cheap once the medical-only pack exists
   and the two-instance pattern is real friction for the common case.
6. Tag and publish as a GitHub Release; keep the last N releases so a consumer can pin.

## Two corrections from reading spellkit's source (2026-09-06)

Both were found while building the gem, and both invalidate a specific claim made earlier in
this file. Recorded here so they are not re-derived later.

### 1. spellkit's download cache never revalidates, so a "latest" URL is a trap

`lib/spellkit.rb`'s `download_dictionary` caches to `~/.cache/spellkit/dict_<hash>.tsv` where
`<hash>` is `SHA256(url)[0..15]`, and its first line of work is
`return cache_file if File.exist?(cache_file)`. There is no TTL, no `If-None-Match`, no
`If-Modified-Since`, and no revalidation of any kind.

So a consumer pointed at `releases/latest/download/dictionary.tsv` downloads exactly once and is
pinned to that snapshot **forever** - every later release is invisible to them, on every boot, on
every hot reload, until someone manually clears the cache. This plan's earlier recommendation to
prefer the `latest` alias for freshness produces the worst possible outcome for freshness.

The fix inverts it: **every URL must be an immutable, version-tagged release asset.** A new pack
version is then a new URL, a new cache key, and a real download. Freshness becomes a gem-version
bump (the registry ships inside the gem and carries the tagged URL), which is a deliberate,
reviewable, lockfile-visible act rather than a silent one. The gem enforces this with a spec that
fails if any registered URL contains `releases/latest/`.

### 2. spellkit cannot download `protected_path`, so this gem needs its own fetcher

`SpellKit#load!` URL-detects the `dictionary:` argument only. `protected_path:` is passed
straight through to the Rust core (`ext/spellkit/src/lib.rs:185`) and is treated as a
filesystem path; handing it a URL fails. A pack is a *pair* of files, so the protected half has
to be fetched by this gem regardless of what spellkit does with the dictionary half.

Given that, the gem fetches **both** halves rather than fetching one and delegating the other:
one cache directory per pack version, one code path, one checksum policy, and no confusing split
between `~/.cache/spellkit/` and this gem's cache. `SpellKit::Dictionaries::Fetcher` verifies a
registered SHA-256 and renames into place only after the checksum passes, so an interrupted or
tampered download can never become a cache hit. It then hands spellkit two local paths, and
spellkit does all the actual loading, indexing and hot-reload work exactly as it does today.

This does not change the "spellkit's core stays pack-free" decision - the fetcher lives in this
gem, not in spellkit.

## Validation: measured 2026-09-06 (first real CHV run)

Ran against UMLS 2026AA + the v10 medical pack. Numbers, then the caveats that bound them.

**The UMLS full release is not a directory of RRF files**, and the member path Substrate's CHV
connector guesses (`{version}/META/MRCONSO.RRF`) does not exist in it. The real layout is
`2026AA-full/2026aa-{1,2}-meta.nlm` (each a zip) plus `mmsys.zip` (MetamorphoSys), with
MRCONSO living inside the first as three independently-gzipped, line-safe parts
(`2026AA/META/MRCONSO.RRF.{aa,ab,ac}.gz`, 18,064,970 lines reassembled, 0 malformed). Also
`2025AB` is stale; `2026AA` is current. **Both are latent bugs in substrate's own connector**
and worth folding into substrate#2806.

**CHV is not a misspelling list.** This is the finding that most changes how the corpus may be
used. Of 5,195 drug pairs, only 1,325 are single-token -> single-token; the rest are word-order
permutations ("0 9 chloride injection sodium") and formulation restatements ("0.45% sodium
chloride" -> "sodium chloride 0.0769 meq/ml"). And even the single-token remainder maps by
MEANING, not spelling: it contains abbreviations (`adr` -> doxorubicin, `na` -> sodium, `cyts`
-> cyclophosphamide) that no edit-distance corrector can ever reach, plus morphological
variants (`accutanes` -> accutane, `5-fluorouracil` -> fluorouracil) alongside true typos
(`acetobutolol` -> acebutolol). Scoring the unreachable ones as errors dragged the recommended
`frequency_threshold` to 1000, i.e. a checker that corrects nothing. `bin/validate` therefore
filters to single-token pairs within edit distance 2 by default.

**Coverage fix (2026-09-06, same day).** The first measurement missed 26% of correction
targets. The cause was not licensing and not a missing ingest: RxNorm is tier `none` and
Substrate already holds the full graph in `silver.silver_rxnorm` (219,237 rows with TTY). The
blocker was that the export ran as `explore_ro`, which cannot read `silver` - a least-privilege
choice stricter than PLAN.md's own data-access section calls for. Reading the curated TTYs
(IN/PIN/MIN/BN) took targets-not-in-dictionary from 172 to **3**, and scorable pairs from 398
(61%) to **542 (83%)** - 484 typos corrected against 357, a 36% larger addressable set at flat
recall. Formulation TTYs (SCD/SBD/GPCK) are excluded: they are multi-word strings a unigram
index cannot use.

**Results** on the 652 orthographically-reachable pairs (542 scorable after the coverage fix;
360 in the first pass):

| edit_distance | frequency_threshold | recall | error rate |
|---|---|---|---|
| 1 | 1 | 71.9% | 7.8% |
| 1 | 100 | 14.2% | 2.5% |
| **2** | **1** | **88.6%** | **11.4%** |
| 2 | 10 | 58.3% | 14.4% |

Provisional pack default: **`edit_distance: 2`, `frequency_threshold: 1.0`**. The 2% harm
ceiling this repo ships as `--max-error-rate`'s default is miscalibrated for this corpus -
nothing useful clears it - so the number above was chosen at a 12% ceiling and is a JUDGEMENT,
not something the sweep settled on its own.

**THE MEDICAL PACK ALONE IS NOT SAFE FOR GENERAL TEXT, and the harness hid this for three
rounds.** Measured on the v10 build at the recommended tuning, `medical` rewrites **87.5% of
the thousand commonest English words** - "the" -> "dhe", "and" -> "aid", "with" -> "witch" -
while `general_medical` scores **0.0%** on the same probe and fixes MORE drug typos (5/5 vs
4/5). This is inherent to any domain-only dictionary: with no English in the index, every
ordinary word is an unknown to be corrected.

It went unseen because every pair in the corpus is a known misspelling, so the harness only
ever asked "is this typo fixed?" and never "is correct text left alone?" - and the second
question covers the majority of real input. `bin/validate` now reports the false-positive rate
on common English on every run, and a spec reproduces the failure in miniature. **A recall
number from a misspelling corpus is not evidence that a pack is safe.** `general_medical` is
the default anyone should reach for; `medical` is for callers who filter tokens themselves.

**Lift over a generic English spellchecker**, the number that decides whether the pack is worth
shipping at all. Both scored over the same denominator (all 652 pairs), so a baseline that
cannot reach a target counts it as a miss rather than shrinking its own denominator:

| | corrections | wrong | unchanged |
|---|---|---|---|
| generic English (en-80k) | 59 (9.0%) | 104 | 489 |
| `general_medical` | **451 (69.2%)** | **63** | 138 |

403 pairs are fixed only by the pack; 11 only by English. 7.6x the corrections AND fewer wrong
answers. The 11 are mostly not regressions: `aluminium`, `frusemide`, `glycerine`, `amfetamine`
are valid British/INN spellings the pack legitimately CONTAINS and therefore leaves alone,
where CHV asserts a single canonical target.

**Caveat on the framing**: a corpus of drug misspellings favours a drug dictionary by
construction, so this measures the lift on domain-shaped input, not on real traffic whose mix
is unknown. What makes it decisive anyway is the pairing with the false-positive result -
large gain on domain input, **0.0%** measured harm on ordinary English - so it is upside
without a measured downside, not a trade.

A hand-picked regression list is a bad instrument here and flattered the pack badly: en-80k
already contains acetaminophen, diabetes, metformin, psoriasis and ibuprofen, so a generic
checker scores 5/8 on the typos this project started from. The pack earns its place on brand
names and newer drugs - flexeril, semaglutide, pembrolizumab - which no general word list
carries.

**Do not quote 88.6% as a typo-correction rate.** It is a consumer-form-to-canonical-form rate
over a filtered slice, and the residual "wrong" cases are dominated by genuine ambiguity
(`bromocryptin` -> bromocriptin when bromocriptine was wanted) and by dictionary variants that
should not be there (`5fluorouracil`). Dictionary coverage, not tuning, is the bigger lever
left: 179 of 652 targets are absent from the pack entirely, and 113 misspellings are themselves
dictionary terms.

Before calling a release good:
- Round-trip check: every term in the input source list must itself be `correct?` after loading
  the built dictionary (a term can't fail to recognize itself).
- Once CHV lands: hold out CHV's misspelling -> concept pairs as a test set, measure
  precision/recall of `SpellKit.correct()` against them, and use it to tune `edit_distance` and
  `frequency_threshold` empirically instead of by guess.
- Regression check against the exact typos that started this thread (Flexerol/Flexiril ->
  Flexeril) as a permanent smoke test.

## Open question: phonetic fallback

spellkit is edit-distance-only (SymSpell). Some real misspellings are phonetic rather than
typo-adjacent (dropped/added silent letters, sound-alike substitutions) and won't fall inside
edit-distance 2. Whether that gap matters in practice is only answerable once CHV validation data
exists (see above). If it does, the fix is a phonetic-match fallback (e.g. Double Metaphone) added
natively to spellkit's Rust core as its own proposal - explicitly out of scope here, and not
worth building speculatively before the CHV validation pass says it's needed.

## Sequencing relative to Substrate work

1. Substrate: `distance => 2` fuzzy-match fix on the live BM25 search - **done, merged, PR #2746**.
2. Substrate: ingest CHV as a new source - **done, merged, PR #2767**, and further: manually run
   against the live serving generation (substrate-db-production-v10) on 2026-09-06, ahead of the
   normal monthly cycle. Real data is live: `restricted.restricted_drug_misspelling` has 4,725
   misspellings across 1,931 distinct drugs, backed up. Two real bugs found running it for the
   first time against real UMLS data are filed as substrate#2806 and substrate#2807 (a stale
   URL/version default, and an unindexed-correlated-subquery test that only showed its cost at
   real scale) - both in progress as of this writing.
3. **Substrate: the dictionary-source export script - NOT YET STARTED, and blocks step 4.** See
   "Data access: resolved" above. This is the next concrete piece of work and it lives in the
   `substrate` repo, not here.
4. **This repo: the `spellkit-dictionaries` GEM - done, 2026-09-06.** The plugin half of step 5
   turned out to have no dependency on step 3 at all, so it was built first. It reopens `SpellKit`
   to add `enable_dictionary` / `dictionary_checker`, ships the pack registry in `data/packs.yml`,
   and fetches + checksum-verifies + caches pack artifacts. `:medical` and `:general_medical` are
   registered with `release: null`, so calling them raises `PackNotReleasedError` pointing at this
   file rather than 404ing. 48 specs, green, run against the real spellkit native extension.
   **spellkit's own repo was not touched, exactly as the 2026-09-06 revision above requires.**
5. This repo: the v0 BUILD PIPELINE - **medical built and verified 2026-09-06** against a real
   `substrate-db-production-v10` export (275,936 source terms -> 126,461 dictionary terms,
   89,953 protected). Corrects 10/10 of the regression typos at `edit_distance: 2`,
   `frequency_threshold: 10.0`. NOT YET RELEASED: the tuning is a spot-check, not the CHV
   sweep, and `general_medical` (the English merge) is still unbuilt. Formerly described as: Everything downstream of it is already in
   place: publishing a release and flipping `release: null` to a real tag + sha256 in
   `data/packs.yml` is all that stands between the export existing and `enable_dictionary(:medical)`
   working. Note step 5 was previously described as "the thin `SpellKit::Dictionaries` pointer-registry
   PR against spellkit"; that PR no longer exists as work, having been replaced by the gem in (4).
6. Integration ticket (Substrate): explore's search box calls spellkit with the published
   dictionary to correct/expand a query term before it hits ParadeDB - separate scoped work, not
   part of this repo, not started.

### Next up: an IUPAC / systematic-chemical-name pack (Chris, 2026-09-06)

Decided AFTER the medical pack, but ahead of any other domain pack. The question was whether
`ethyl-methyl-...` style systematic names can be spellchecked at all, catching obvious typos
without flagging things that are probably right.

**SymSpell over whole IUPAC names is structurally the wrong tool and must not be attempted.**
IUPAC names are generative, not enumerable - `(2S)-2-[4-(2-methylpropyl)phenyl]propanoic acid`
is a sentence in a grammar, not a word in a list, and there are unboundedly many valid ones. A
dictionary corrector can only ever correct what it lists.

The morphemes, however, ARE a small closed set (hundreds to low thousands): multiplying
prefixes (di/tri/tetra), stems (meth/eth/prop/but/pent/hex), suffixes (-ane/-ene/-ol/-one/
-oic acid/-yl/-amide), substituents (hydroxy/chloro/amino/nitro/phenyl/benzyl), ring systems
(benzen/pyridin/imidazol/naphthalen), locants and stereodescriptors. So: tokenize into
morphemes, then spellcheck the morphemes. Three layers, ordered by precision:

1. **Structural checks - no dictionary, near-zero false positives.** Unbalanced brackets;
   multiplier/locant disagreement (`2,3,4-dimethyl` has three locants but `di` says two); a
   locant that cannot exist (`7-methylhexane`); malformed locant punctuation; stereodescriptors
   outside the legal set. Each of these is essentially always an error, never a variant.
2. **Morpheme dictionary at edit distance 1, flagging ONLY when a known morpheme is within
   distance 1.** Unknown-and-far means a rare-but-valid morpheme or a trade name - stay silent.
   This is already how spellkit behaves (`correct` returns its input when nothing is close), so
   the precision-first requirement and the engine's default agree.
3. **OPSIN round-trip** (Open Parser for Systematic IUPAC Nomenclature) - highest precision by
   a wide margin; a name it cannot parse is a strong wrongness signal. Java, so realistically a
   build-time/CI validator rather than something in-process in a Ruby app. Its accuracy is
   believed high on well-formed names but is UNVERIFIED here - check before relying on it.

Recommendation: layers 1 and 2, shipped as a `chemistry` pack whose dictionary is morphemes
rather than names. **The real gap is a morpheme tokenizer, which spellkit does not have** - it
splits on whitespace, and `2-methylpropyl` is one whitespace token. That tokenizer belongs in
this gem, not in spellkit's Rust core. Deliberately NOT added to `data/packs.yml` yet: the
registry's `release: null` means "specified but unpublished", and this is not specified yet.

## Sequencing relative to Substrate work

**For an agent picking this up cold**: steps 1, 2 and 4 are done. **Step 3 (the Substrate export
script) is the actual next task and has no code yet** - start there, in the `substrate` repo, not
here. This repo's remaining work (step 5) has nothing to consume without it. When writing that
export, read "CHV cannot ship in a public artifact" above first: it constrains which columns the
export may expose for publication. This file plus this repo's README are the only design record;
there is no GitHub issue for step 3 or step 5 yet.

## Explicit non-goals

- Not a new Magnus/Rust gem - spellkit already is that gem.
- Not a Substrate warehouse write path - read-only consumer, same as any other downstream product.
- Not a phonetic-matching engine - flagged above as a possible follow-up against spellkit itself,
  not built here speculatively.
