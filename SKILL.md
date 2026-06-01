---
name: notebooklm
description: "Turn expert podcasts into personalized protocols with cited experiments. Load 300 episodes from terminal, run an expert-informed interview, build experiments in your Obsidian morning routine. Use when user says \"notebooklm\", \"load channel\", \"expert interview\", \"notebooklm ask\", \"health protocol\", or wants to turn expert content into actionable experiments."
---

# NotebookLM - Expert Knowledge to Action

Turn any expert's content into a personalized protocol with experiments you actually run. Load 300 YouTube episodes into NotebookLM from terminal, run a cited interview about your goal, create experiments in your Obsidian daily note.

**Video walkthrough:** [https://youtu.be/KRpZSvtMiTI](https://youtu.be/KRpZSvtMiTI)

## What This Does

1. **Load sources from terminal.** You can't just tell NotebookLM to add a YouTube channel. This skill does it. One command. 300 episodes.
2. **Cited answers traced to exact transcript lines.** Every recommendation links back to the exact episode and passage. Verifiable.
3. **Expert-informed interviews.** Claude queries NotebookLM with YOUR goal. Generates questions informed by the expert's research on your specific topic.
4. **Experiments in Obsidian.** Protocol becomes experiments in your daily note. Morning routine skill asks every day: how is this going?
5. **Any expert, any domain.** Huberman for health. Lenny for product. Onboarding docs for a new job. Same pattern.

## Prerequisites

### 1. Install nlm CLI

```bash
uv tool install notebooklm-mcp-cli
```

Gives you the `nlm` command. See [notebooklm-mcp-cli](https://github.com/jacob-bd/notebooklm-mcp-cli) for details.

### 2. Install notebooklm-py (for notebook creation and channel loading)

```bash
uv tool install "notebooklm-py[browser]"
uvx --from "notebooklm-py[browser]" playwright install chromium
```

This installs the `notebooklm` command in its own isolated environment (no system-Python pollution, works even with a Homebrew/PEP-668 Python). The matching Chromium build is installed for the browser automation.

> If you prefer a plain pip install: `pip install "notebooklm-py[browser]" && playwright install chromium`. On a Homebrew-managed Python you may need `--break-system-packages`.

### 3. Authenticate

You need **two** logins — the tools are independent projects with separate sessions:

```bash
# nlm: read side (queries + source listing). Borrows cookies from a
# Chromium-family browser you're already signed into. Session ~20 min.
nlm login

# notebooklm-py: write side (notebook creation + channel loading).
# Opens its own Chromium for a fresh Google login. Session lasts weeks.
notebooklm login
```

`notebooklm-py` saves cookies to `~/.notebooklm/profiles/default/storage_state.json`. Check `nlm` with `nlm notebook list` (empty `[]` = authenticated, just no notebooks yet).

### 4. Obsidian Plugins

- **Dataview** (required) - for dashboard queries and citation tables

## Quick Start

```bash
# List your notebooks
nlm notebook list

# Ask a question with citations
nlm notebook query <notebook-id> "What does Huberman say about deep focus?" --json

# List sources
nlm source list <notebook-id> --json
```

## Workflow Routing

| User says | Workflow |
|-----------|----------|
| "load channel", "youtube channel", "bulk load videos" | [workflows/youtube-channel.md](workflows/youtube-channel.md) |
| "notebooklm ask", "ask notebook", "Q&A" | [workflows/ask.md](workflows/ask.md) |
| "import notebook", "import sources" | [workflows/import.md](workflows/import.md) |
| "notebooklm auth", "notebooklm login" | [workflows/auth.md](workflows/auth.md) |

## The Full Pipeline

This is the workflow shown in the video:

### 1. Pick your expert and goal

```
Goal: "I want to improve my health and focus"
Expert: Andrew Huberman (@hubermanlab on YouTube)
```

### 2. Load their content

```bash
# Scrape channel videos (no auth/deps needed — pure stdlib)
python3 scripts/load_channel.py scrape \
  --channel "https://www.youtube.com/@hubermanlab" \
  --output /tmp/huberman-videos.json

# Create notebook (grab the printed <notebook-id>)
notebooklm create "Andrew Huberman - Health"

# Load the 300 most recent episodes.
# Run via `uv run --with` so the script can import notebooklm-py from its
# isolated tool env. Videos are newest-first, so this keeps the latest 300.
uv run --with "notebooklm-py[browser]" python3 scripts/load_channel.py load \
  --videos /tmp/huberman-videos.json \
  --notebook <notebook-id> \
  --count 300 \
  --concurrency 6
```

> **Source cap depends on tier: free = 50, NotebookLM Plus/Pro = 300 per notebook.** `--count 300` assumes Plus/Pro. On a free account only ~50 ingest and the rest become red, empty rows — use `--count 50` there. Confirm both `nlm` and `notebooklm` are logged into the *same* account with that tier (`notebooklm auth check`).
>
> **Keep `--concurrency` low.** Higher concurrency causes some adds to fail (red rows whose title is the raw URL), even on Plus. At `--concurrency 1` they essentially disappear. After loading, check the real split:
> ```bash
> nlm source list <notebook-id> --json | python3 -c "import json,sys;d=json.load(sys.stdin);r=[s for s in d if s['title'].strip().startswith('http')];print(f'good {len(d)-len(r)}  red {len(r)}')"
> ```
> To repair reds: delete the red rows (`nlm source delete <id> --confirm`) and re-add those videos at `--concurrency 1`.

### 3. Ask expert-informed questions

```bash
nlm notebook query <notebook-id> \
  "What does Huberman recommend for sustaining deep focus for 4+ hours daily?" --json
```

Each answer comes with `[N]` citations back to the exact source and passage.

### 4. Run a cited interview

Claude uses the notebook to generate interview questions specific to YOUR goal. You answer honestly. Claude builds a personalized protocol where each recommendation is tied to an exact episode.

### 5. Create experiments

The protocol becomes experiments in your Obsidian vault:
- Each experiment has a hypothesis, protocol, success criteria, and timeframe
- They appear in your daily note every morning
- Your morning routine skill asks: "How is this experiment going? Any observations?"

### 6. Turn it into a reusable skill

Package the workflow as a `/huberman` or `/lenny` skill. Same pattern, different expert.

## Vault Structure

```
Your Vault/
├── Notes/NotebookLM/
│   ├── Huberman Health.md              # type: notebook (index)
│   └── huberman-health/
│       ├── Sources/                     # type: notebook-source (transcripts)
│       │   └── Episode Title.md
│       └── QA/                          # type: nlm-query (cited answers)
│           └── 2026-04-05 Focus Protocol.md
├── Notes/Experiments/
│   └── Morning Sunlight Protocol.md     # type: experiment
└── Notes/Dashboards/
    └── Health.md                        # Dashboard with embedded experiments
```

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/load_channel.py` | Scrape YouTube channel + bulk-load into NotebookLM |
| `scripts/resolve_citations.py` | Replace `[N]` with `[[Source#^anchor\|[N]]]` wikilinks |
| `scripts/import_sources.py` | Import sources as vault files with metadata |
| `scripts/extract_passages.py` | Extract cited passages from Q&A into source files |
| `scripts/backfill_fulltext.py` | Fetch full transcripts for source files |

All scripts use `Path.cwd()` as vault root. Run them from your vault directory.

## Citation Resolution

The resolver turns `[N]` markers in NotebookLM answers into clickable `[[Source#^c-XXXXXXXX|[N]]]` wikilinks. Click to jump to the exact cited passage in the source transcript.

- Anchor IDs are stable (MD5 of cited text)
- Idempotent: re-running same question skips existing anchors
- Cross-source citation remap: handles collapsed source_ids
- ~96% resolution rate across tested queries

## Examples

- **Health:** 300 Huberman episodes -> personalized health protocol with sleep, supplements, exercise experiments
- **Product:** 200 Lenny's Podcast episodes -> product strategy playbook with cited frameworks
- **New job:** Onboarding docs + team wikis + architecture decisions -> ramp-up plan with daily experiments
- **Business:** Hormozi content -> offer audit with value equation scoring

## License

MIT
