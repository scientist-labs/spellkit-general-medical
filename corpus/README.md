# Validation corpus

This directory holds the held-out corpus used to tune a pack's `edit_distance` and
`frequency_threshold`. **Its contents are deliberately not committed** — see
`../.gitignore`.

## Why it is not in git

The corpus is built from NLM's Consumer Health Vocabulary (CHV): real misspellings that
real people typed, mapped to the concept they meant. CHV has no independent ungated NLM
distribution; it ships only inside the gated UMLS Metathesaurus release. So:

- **Using it here is fine** if you hold a UMLS licence. Reading it to compute a number is
  use, which the licence covers.
- **Committing it would not be.** This repository is public, and pushing the corpus would
  redistribute UMLS content to everyone who clones — which the licence does not permit.

What leaves this directory is two numbers (`edit_distance`, `frequency_threshold`) plus
aggregate accuracy figures, published in `data/packs.yml` and the release notes. Those are
measurements derived from the corpus, not the corpus. Never publish row-level
misspelling/term pairs — that would reconstruct CHV.

## How to reproduce it

You need your own UMLS licence and API key (free for most uses, but you must
[sign up](https://uts.nlm.nih.gov/uts/signup-login) and accept the licence).

```bash
export UMLS_API_KEY=...
bin/fetch_chv
```

That downloads the UMLS Metathesaurus full release (**several GB**), extracts
`MRCONSO.RRF`, keeps the `CHV` and `RXNORM` atoms, joins a consumer misspelling to the
RxNorm name sharing its CUI, and writes `chv_drug_misspellings.tsv` here.

Already have `MRCONSO.RRF` extracted? Skip the download entirely:

```bash
bin/fetch_chv --mrconso /path/to/MRCONSO.RRF
```

Pin a different release with `--umls-version 2025AB` (the URL carries the version; NLM
publishes no `current` alias, so this is a manual bump twice a year).

## Format

Any file this harness reads is a two-column TSV — `misspelling<TAB>correct term` — with
`#` comments and blank lines ignored. You do not have to use CHV: point `bin/validate` at
any corpus in that shape with `--corpus`.

```
acetominophen	acetaminophen
flexerol	flexeril
```

## Scope

CHV's drug coverage is what this join reaches: misspellings whose concept has an RxNorm
atom. Conditions, symptoms and procedures are a different join path and are not included,
so constants tuned here are measured on **drug** misspellings and then applied to a pack
that also contains conditions and gene symbols. Say so in the release notes rather than
implying the whole pack was validated.
