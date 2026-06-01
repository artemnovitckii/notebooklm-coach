# NotebookLM Coach — a Claude Code skill

Turn any expert's podcast/video library into a **personal coach that cites its sources**. Bulk-load hundreds of YouTube episodes into NotebookLM from your terminal, ask questions and get answers traced to the exact transcript passage, then turn the advice into a protocol you actually follow.

Give it the Huberman Lab channel and it becomes a health coach. Give it Lenny's Podcast and it's a product coach. Same pipeline, any expert.

> **Credit:** This is an adapted, fixed fork of the `notebooklm` skill from [ArtemXTech/personal-os-skills](https://github.com/ArtemXTech/personal-os-skills). All original design credit to that author. See [What's different](#whats-different-in-this-fork) for the changes.

---

## What it does

1. **Load sources from the terminal.** NotebookLM's UI won't let you add a whole YouTube channel. This does — one command, up to 300 episodes.
2. **Cited answers.** Every recommendation links back to the exact episode and spoken passage. Verifiable, not vibes.
3. **Expert-informed interview.** Claude queries the notebook with *your* goal and builds a personalized, source-backed protocol.
4. **Any expert, any domain.** Health, product, business, onboarding — same pattern.

---

## Prerequisites

You need three tools: **Claude Code**, **NotebookLM** (a free Google account), and optionally **Obsidian** (for the vault/notes side).

### 1. Install the two CLIs

```bash
# Read side: query notebooks + list sources
uv tool install notebooklm-mcp-cli

# Write side: create notebooks + bulk-load channels (+ its browser)
uv tool install "notebooklm-py[browser]"
uvx --from "notebooklm-py[browser]" playwright install chromium
```

Using `uv tool` keeps each CLI in its own isolated environment — no system-Python pollution, and it works even on a Homebrew/PEP-668 Python. (Don't have `uv`? See [astral.sh/uv](https://docs.astral.sh/uv/).)

### 2. Authenticate (two separate logins)

These are two independent projects with separate sessions — you need both:

```bash
nlm login          # read side. Borrows cookies from a Chromium-family
                   # browser you're already signed into. Session ~20 min.
notebooklm login   # write side. Opens its own Chromium for a fresh
                   # Google login. Session lasts weeks.
```

Verify: `nlm notebook list` — an empty `[]` means you're authenticated with no notebooks yet.

### 3. (Optional) Obsidian

Enable the **Dataview** community plugin if you want the cited answers, sources, and experiments written into an Obsidian vault.

---

## Install the skill

Clone this repo straight into your Claude Code skills directory:

```bash
git clone https://github.com/artemnovitckii/notebooklm-coach.git ~/.claude/skills/notebooklm
```

Restart Claude Code (or start a new session) and the `notebooklm` skill is available. Just say *"notebooklm"*, *"load channel"*, or *"health protocol"*.

---

## Quick pipeline (Huberman example)

```bash
# 1. Scrape the channel (pure stdlib, no auth needed)
python3 ~/.claude/skills/notebooklm/scripts/load_channel.py scrape \
  --channel "https://www.youtube.com/@hubermanlab" \
  --output /tmp/huberman-videos.json

# 2. Create a notebook (note the printed <notebook-id>)
notebooklm create "Andrew Huberman - Health"

# 3. Load the 300 most recent episodes (run via `uv run --with` so the
#    script can import notebooklm-py from its isolated tool env)
uv run --with "notebooklm-py[browser]" python3 \
  ~/.claude/skills/notebooklm/scripts/load_channel.py load \
  --videos /tmp/huberman-videos.json \
  --notebook <notebook-id> \
  --count 300 --concurrency 6

# 4. Verify how many sources actually landed
nlm source list <notebook-id> --json | grep -c '"id"'

# 5. Ask a cited question
nlm notebook query <notebook-id> \
  "What does Huberman recommend for sustaining deep focus?" --json
```

From here, let Claude run the interview and build your protocol — that's what the skill orchestrates.

---

## Gotchas (read these — they'll save you an hour)

- **Source cap is per *tier*: free = 50, NotebookLM Plus/Pro = 300 sources per notebook.** This is the single biggest trap. If you load 300 on a *free* account, the first ~50 ingest and the rest show up as **red, empty rows** — it looks like a bug but it's the tier limit. The loader defaults to `--count 300` (the Plus number); on free, use `--count 50`. For full coverage on free, split a big channel across multiple notebooks and query them together with `nlm cross`.

- **Make sure BOTH logins are the same, correct account.** `nlm login` (read) and `notebooklm login` (write) authenticate independently and each defaults to whatever Google account your browser is already signed into — so they can silently land on *different* accounts, or on a free account when your Plus is elsewhere. Verify: `nlm login profile list` and `notebooklm auth check`. To switch: `nlm login --clear` (fresh browser → pick the right account) and `notebooklm auth logout && rm -rf ~/.notebooklm/browser_profile && notebooklm login`.

- **Reds = failed adds; you can spot and repair them.** A failed source keeps the raw **URL as its title** (NotebookLM never fetched the video). Higher `--concurrency` causes more of them (an ingest race), even on Plus — at `--concurrency 1` they essentially disappear. To repair: delete the red rows and re-add at low concurrency.
  ```bash
  NB=<notebook-id>
  # delete every red row (title is a URL)
  nlm source list $NB --json | python3 -c "import json,sys;[print(s['id']) for s in json.load(sys.stdin) if s['title'].strip().startswith('http')]" \
    | while read id; do nlm source delete "$id" --confirm; done
  # then re-add the missing videos at --concurrency 1
  ```
  Verify the real good/red split anytime:
  ```bash
  nlm source list $NB --json | python3 -c "import json,sys;d=json.load(sys.stdin);r=[s for s in d if s['title'].strip().startswith('http')];print(f'good {len(d)-len(r)}  red {len(r)}')"
  ```

- **`nlm` sessions are short (~20 min).** If queries start failing with auth errors, just re-run `nlm login`. The `notebooklm` (write) session lasts weeks.

- **Processing lag.** After upload, NotebookLM indexes each transcript server-side (a few minutes). Early queries may be thin until processing finishes.

---

## What's different in this fork

Fixes that make it work as of mid-2026:

- **YouTube scraper fixed.** YouTube migrated channel listings from `videoRenderer` → `lockupViewModel`; the original parser silently returned **0 videos**. Added a `lockupViewModel` parser (`scripts/load_channel.py`).
- **300-source cap enforced** in the loader, with a clear message when a channel exceeds it.
- **Lower default concurrency (20 → 6)** so success/failure reporting is honest, plus a documented warning about the false-failure behavior.
- **Corrected auth docs:** the current `nlm` CLI uses `nlm login`, not `nlm auth login`.
- **Install via `uv tool`** (isolated, PEP-668-safe) and run the loader via `uv run --with` instead of assuming a `~/projects/notebooklm-loader` virtualenv.
- **Documented the real-world traps** that the original glossed over: the per-tier source cap (free 50 / Plus 300), the two-logins-must-match-account pitfall, and how to detect & repair red (failed) sources. See [Gotchas](#gotchas-read-these--theyll-save-you-an-hour).

---

## License

MIT — see [LICENSE](LICENSE). Adapted from [ArtemXTech/personal-os-skills](https://github.com/ArtemXTech/personal-os-skills).
