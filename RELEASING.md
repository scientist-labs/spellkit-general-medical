# Releasing

One artifact now: the gem, with its data vendored inside. There is no separate pack
release and no ordering constraint any more — both disappeared when the data moved into
the gem.

## 1. Rebuild the data

Needs Substrate warehouse access, which is why it is not a CI job.

```bash
# In the substrate repo, against production. Read-only: the select runs inside an
# explicit `begin read only` transaction.
bin/export_dictionary_source.rb --output dict_source.tsv

# Here
bin/build_pack --source dict_source.tsv --out build/medical --merge-english
cp build/medical-general/dictionary.tsv build/medical-general/protected.txt data/
```

Update `TERM_COUNT` and `PROTECTED_COUNT` in `lib/spellkit/general_medical/version.rb`.
Specs assert they match the files, so a stale constant fails the build rather than
misreporting in someone's boot log.

## 2. Validate

```bash
bin/fetch_chv                                   # needs your own UMLS_API_KEY
bin/validate --dictionary data/dictionary.tsv \
             --protected  data/protected.txt --max-pair-distance 2
```

Three numbers gate a release, and the second is the one that is easy to skip:

- **Recall** on reachable pairs — how many typos it fixes.
- **Correctly-spelled common English mangled** — must be ~0%. A recall figure alone will
  not catch this: an earlier build scored 89% recall while rewriting 87.5% of the thousand
  commonest English words.
- **Lift over generic English** — whether the pack beats an ordinary word list at all. It
  is easy to over-credit the pack here, since en-80k already carries `acetaminophen`,
  `diabetes` and `metformin`.

Also re-measure **RSS**, and put it in the README. Memory is a shipped property of the
tuning: `edit_distance: 2` costs ~2.1 GB against ~484 MB at 1, and a default that OOMs a
container is a defect regardless of its recall.

## 3. Release

```bash
# bump lib/spellkit/general_medical/version.rb, commit, then:
git tag 1.1.0 && git push origin HEAD --tags
```

CI adopts `scientist-labs/rust-gem-release@0.11.0` as a pure-Ruby caller and publishes with
the org's shared `RUBYGEMS_API_KEY`. Dry-run any time from Actions → Run workflow with the
version box blank.

## 4. Verify as a consumer

```bash
gem install spellkit-general-medical
ruby -e 'require "spellkit-general-medical"
         SpellKit.enable_dictionary(:general_medical)
         puts SpellKit.correct("flexerol")   # => flexeril
         puts SpellKit.correct("the")        # => the'
```
