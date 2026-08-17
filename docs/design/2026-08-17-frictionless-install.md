# Frictionless install — design

**Date:** 2026-08-17
**Status:** approved, implementing

## Goal

A viewer pastes the repo URL into Claude Code, says "install this," and ends up with a
working skill: both CLIs installed and a clear report of what still needs a human.

Success = two permission prompts (clone, bootstrap) and one printed next-step list.

## Constraints

These are fixed by the platform, not by choices we can revisit:

- **Nothing runs at install time.** Cloning into `~/.claude/skills/` executes nothing, and
  Claude Code plugins have no post-install lifecycle hook. Any setup must be triggered
  *after* the files land.
- **The two logins cannot be automated.** `nlm login` and `notebooklm login` open a browser,
  require Google 2FA, and block on a keypress. Running them from a tool call hangs with a
  blank screen. They stay the human's job.
- **Permission prompts have a floor.** Claude Code gates Bash calls. We minimise the count;
  we cannot reach zero without telling viewers to weaken their own guardrails, which we
  will not do.

## Approach

Agent-directed README. A short block at the top of `README.md` tells Claude what to do when
someone pastes the repo. All install logic lives in one readable script.

Rejected: plugin + marketplace (still needs the same script, and costs the viewer two exact
slash commands instead of a paste); `curl | sh` (asks strangers to pipe a remote script into
a shell, and removes the agent from a demo whose point is the agent).

The agent block is kept short, honest, and strictly a subset of what the human-facing README
says. It must never instruct the agent to do something the human isn't also told about.

## Components

### `scripts/bootstrap.sh`

Idempotent, safe to re-run, exits nonzero on any failure. Two modes: full run, and `--check`
(probe only, install nothing).

Phases, each failing loud with one actionable next command:

1. **Platform gate** — macOS or Linux. Otherwise: advise WSL, exit 1.
2. **uv** — if absent, `brew install uv` when Homebrew exists, else Astral's installer.
3. **PATH check** — confirm the uv tool bin dir is on `PATH`. Without this, installs succeed
   and `nlm` is still "command not found" — the most confusing possible failure.
4. `uv tool install notebooklm-mcp-cli`
5. `uv tool install "notebooklm-py[browser]"`
6. `uvx --from "notebooklm-py[browser]" playwright install chromium` — slowest step;
   announces itself so a long pause doesn't read as a hang.
7. **Auth probe** — non-fatal. Records whether each CLI is logged in.
8. **Report** — installed/logged-in state per CLI, plus the exact commands for whatever is
   missing.

Never runs the logins. Never loads a channel.

### `SKILL.md` step 0

Every workflow runs `bootstrap.sh --check` first. Cheap, and it catches anyone who installed
the skill by other means before they hit `command not found` mid-channel-load.

### The report

Carries the two traps that cost the most time, stated as rules rather than detected values
unless the CLIs actually expose them:

- Both CLIs must be on the **same Google account** — they authenticate independently and
  each defaults to whatever the browser is signed into.
- Source cap is **per tier**: free = 50, Plus/Pro = 300. Loading 300 on free yields ~50 good
  sources and a wall of red empty rows that looks like a bug.

## Out of scope

No Windows script (WSL message instead). No automated login. No auto-loading a channel. No
plugin conversion. Each is real work that doesn't serve "paste link, get set up."

## Findings from implementation

**Shim collision (fatal, fixed).** `notebooklm-mcp-cli` and `notebooklm-py` both ship an
executable named `notebooklm-mcp`. Whichever installs second aborts with
`Executable already exists`, leaving its own CLI uninstalled — so a naive install ends with
`nlm` present and `notebooklm` silently missing. The script detects this specific error and
retries with `--force`. Only the shared `notebooklm-mcp` name is contested; `nlm` and
`notebooklm` both survive, and the skill uses neither of the MCP shims.

**Auth probe.** Both `nlm notebook list` and `notebooklm auth check` exit nonzero when not
authenticated — verified. The logged-in case is inferred from exit 0 and remains unverified
until someone completes the browser logins. Worst case is a false "not logged in", which
costs a no-op login command.

**Account and tier are not detected.** `notebooklm auth check` prints a diagnostic table,
not a parseable account or tier. The report states the same-account and tier-cap rules as
warnings rather than printing a confidently wrong value.
