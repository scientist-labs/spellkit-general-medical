# Releasing

Two things ship from this repo, **independently and in a fixed order**.

| | What | Where it runs | Trigger |
|---|---|---|---|
| **Pack** | `dictionary.tsv` + `protected.txt` | Operator laptop (needs warehouse access) | manual |
| **Gem** | `spellkit-dictionaries` (Ruby pointers) | GitHub Actions | version tag |

They are versioned separately on purpose (PLAN.md): shipping `medical-v3` must not force a
consumer of another pack to do anything.

## Order matters

**Publish the pack release BEFORE the gem that points at it.**

The registry ships *inside* the gem. If gem 1.0.0 names `general-medical-v1` and that GitHub
Release does not exist yet, then every consumer who installs the gem gets a `DownloadError` on
their first `enable_dictionary` call — and the only fix is another gem release. There is no
server-side registry to correct after the fact.

## 1. Build the pack

Needs Substrate warehouse access, which is why it is not a CI job. See PLAN.md for why the
export lives in the substrate repo.

```bash
# In the substrate repo, against production. Read-only; the select runs inside
# an explicit `begin read only` transaction.
bin/export_dictionary_source.rb --output dict_source.tsv

# Here
bin/build_pack --source dict_source.tsv --out build/medical --merge-english
```

That writes `build/medical/` (domain-only) and `build/medical-general/` (merged).

## 2. Validate before publishing

```bash
bin/fetch_chv                                              # needs your own UMLS_API_KEY
bin/validate --dictionary build/medical-general/dictionary.tsv \
             --protected  build/medical-general/protected.txt --max-pair-distance 2
```

Three numbers gate a release, and the second one is the one that is easy to skip:

- **Recall** on reachable pairs — how many typos it fixes.
- **Correctly-spelled common English mangled** — must be ~0% for any pack meant for general
  text. A domain-only pack scores ~87% here and is unsafe outside pre-filtered input. This
  number is why `general_medical` exists; a recall figure alone will not catch it.
- **Lift over generic English** — whether the pack beats an ordinary word list at all.

## 3. Publish the pack

```bash
gh release create general-medical-v1 \
  build/medical-general/dictionary.tsv \
  build/medical-general/protected.txt \
  --title "general_medical v1" --notes-file notes.md
```

Release notes must carry the upstream attributions (RxNorm, MeSH, Open Targets) and state that
tuning was measured on drug misspellings only.

## 4. Point the registry at it

`bin/release_pack` computes the checksums from the files you are actually uploading, so they
are never hand-copied — a registry `sha256` that disagrees with its asset turns every
consumer's first fetch into a `ChecksumError`.

```bash
bin/release_pack --pack general_medical --dir build/medical-general \
  --tag general-medical-v1 --date "$(date +%F)" \
  --edit-distance 2 --frequency-threshold 1.0
```

Paste the emitted block into `data/packs.yml` under that pack, replacing `release: null`.

**Never point a registry URL at `releases/latest/download/...`.** spellkit caches by
`SHA256(url)` with no TTL and no revalidation, so a floating URL pins every consumer to
whatever snapshot they downloaded first, permanently. A spec fails the build if one appears.

## 5. Release the gem

```bash
# bump lib/spellkit/dictionaries/version.rb, commit, then:
git tag 1.0.0 && git push origin HEAD --tags
```

CI (`.github/workflows/release.yml`) adopts `scientist-labs/rust-gem-release@0.11.0` as a
pure-Ruby caller — same shape as `thor-interactive` and `ragnar-cli` — and publishes with the
org's shared `RUBYGEMS_API_KEY`. Dry-run any time from Actions → Run workflow with the version
box blank.

## 6. Verify as a consumer would

```bash
gem install spellkit-dictionaries
ruby -e 'require "spellkit-dictionaries"; SpellKit.enable_dictionary(:general_medical)
         puts SpellKit.correct("flexerol")   # => flexeril
         puts SpellKit.correct("the")        # => the'
```
