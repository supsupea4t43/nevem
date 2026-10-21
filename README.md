# nevem

Analysis of where the [Appats Model Tracker](https://github.com/supsupea4t43/appats-tracker) loses models, using its own `live_chart/data.json` (refreshed 2026-10-20).

```
git clone --depth 1 https://github.com/supsupea4t43/appats-tracker
python3 requirement_gaps.py appats-tracker/live_chart/data.json
```

`requirement_gaps.py` is stdlib-only and read-only. Its pass rule matches the tracker's: its count of 30 qualifying models equals the tracker's own "30 of 115 models qualify".

## Findings

Of 887 model-at-host offerings, 47 (30 models) meet every Appats requirement.

1. **The DPA gap does not affect the chart.** 58 hosts are "not checked" or "not found", but all of them also fail EU processing, so a DPA for any of them would qualify **0** extra offerings. Researching those hosts is low priority.
2. **Language is the gap worth closing.** 42 more offerings (21 models) fail *only* on Spanish and Catalan:
   - **Claude (15 models, 25 offerings)** are blocked because Anthropic's docs say "most languages" and do not name Catalan. The tracker already has a route for this: `appats_tests.csv` is empty, and a passing Appats test would count under the "Passed Appats' test" filter.
   - **GLM-5.3, Kimi K2.7 Code and gpt-oss (6 models, 17 offerings)** have no row in `languages.csv` at all, so they are "not checked", not "not named".
3. **EU processing** is the largest single blocker (69 offerings, 36 models). That is a property of where hosts run, not missing data.

## Not done

I could not verify the maker language claims in item 2. The session's network policy blocked `huggingface.co`, `arxiv.org`, `docs.z.ai` and `platform.kimi.ai`, and web search returned only secondhand pages. A search snippet suggests the gpt-oss model card evaluates Spanish but not Catalan, but that is unconfirmed. Check the makers' model cards before adding rows to `languages.csv`.
