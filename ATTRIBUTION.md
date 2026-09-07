# Data sources and attribution

The MIT licence in `LICENSE.txt` covers the **code** in this repository. The published pack
artifacts are built from third-party sources, each listed here with what it contributes and
what it requires.

Every source below permits redistribution. Where attribution is required, this file plus the
release notes carry it.

## In the published packs

| Source | Contributes | Licence | Obligation |
|---|---|---|---|
| **RxNorm** (NLM) | Drug ingredient, brand, substance and INN names | Public domain (NLM-authored content; no additional-restriction UMLS source) | Courtesy citation |
| **MeSH** (NLM) | Condition and disease names | Public domain | Courtesy citation |
| **Open Targets / Ensembl** | Gene and target symbols, protein names (also the protected-terms list) | CC0 1.0 | None |
| **SymSpell frequency dictionary** (`en-80k`) | The general-English half of `general_medical` only | SymSpell is MIT (Wolf Garbe); the English frequency list is derived from Google Books Ngram data (CC BY 3.0) and SCOWL | **Attribution — see note below** |

### Note on the English word list

`general_medical` **embeds** SymSpell's `en-80k` list; the `medical` pack does not contain it.

This is worth stating plainly because it differs from what spellkit does: spellkit only ever
*points* at that URL and lets each consumer download it, so spellkit never redistributes the
content. Merging it into a published artifact is redistribution, which is permitted — MIT for
SymSpell, CC BY 3.0 for the underlying Ngram data — but carries an attribution obligation that
pointing at a URL does not. Hence this file.

- SymSpell — https://github.com/wolfgarbe/SymSpell — © Wolf Garbe, MIT licence
- Google Books Ngram data — CC BY 3.0

## Deliberately NOT in the published packs

| Source | Why not |
|---|---|
| **NLM Consumer Health Vocabulary (CHV)** | Ships only inside the gated UMLS Metathesaurus release, so redistributing it to unlicensed third parties is not permitted. Used **locally only**, as a held-out validation corpus. What leaves that process is two tuning constants and aggregate accuracy figures — measurements derived from the corpus, never its rows. See `corpus/README.md`. |

## NLM disclaimer

This product uses publicly available data courtesy of the U.S. National Library of Medicine
(NLM), National Institutes of Health, Department of Health and Human Services. **NLM does not
endorse or claim responsibility for this product**, and it is not reviewed, endorsed or
otherwise approved by NLM or the NIH.

## Scope and honesty note

Tuning was measured against **drug** misspellings only (CHV's drug coverage). The same
constants are applied to condition and gene/target vocabulary, for which no held-out corpus
exists. Treat published accuracy figures as measured on the drug axis, not the whole pack.
