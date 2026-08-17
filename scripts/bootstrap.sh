#!/usr/bin/env bash
#
# bootstrap.sh — install everything the notebooklm skill needs.
#
#   bash scripts/bootstrap.sh            install missing pieces, then report
#   bash scripts/bootstrap.sh --check    report only, install nothing
#
# Exit codes:
#   0  ready to use (or, in --check mode, everything present)
#   1  hard error — something broke and is explained above the exit
#   2  --check only: a dependency or login is missing
#
# Safe to re-run. Never runs the Google logins (they need a browser + 2FA and
# would hang here), and never loads a channel.

set -euo pipefail

CHECK_ONLY=0
if [ "${1:-}" = "--check" ]; then CHECK_ONLY=1; fi

# ---------- output helpers ----------

if [ -t 1 ]; then
  B=$'\033[1m'; DIM=$'\033[2m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; N=$'\033[0m'
else
  B=''; DIM=''; G=''; Y=''; R=''; N=''
fi

step() { printf '\n%s==>%s %s%s%s\n' "$B" "$N" "$B" "$1" "$N"; }
ok()   { printf '  %s✓%s %s\n' "$G" "$N" "$1"; }
warn() { printf '  %s!%s %s\n' "$Y" "$N" "$1"; }
fail() {
  printf '\n  %s✗ %s%s\n' "$R" "$1" "$N"
  if [ $# -gt 1 ]; then printf '    fix: %s\n' "$2"; fi
  exit 1
}
note() { printf '    %s%s%s\n' "$DIM" "$1" "$N"; }

have() { command -v "$1" >/dev/null 2>&1; }

# ---------- 1. platform gate ----------

step "Checking platform"
case "$(uname -s)" in
  Darwin) ok "macOS" ;;
  Linux)  ok "Linux" ;;
  *)      fail "Unsupported platform: $(uname -s)" \
               "run this inside WSL (Windows) — the CLIs are POSIX-only here" ;;
esac

# ---------- 2. uv ----------

step "Checking uv"
if have uv; then
  ok "uv present — $(command -v uv)"
elif [ "$CHECK_ONLY" = 1 ]; then
  warn "uv missing"
else
  if have brew; then
    note "installing via Homebrew"
    brew install uv || fail "brew install uv failed" "install uv manually: https://docs.astral.sh/uv/"
  else
    note "no Homebrew found — using the official installer from https://astral.sh/uv"
    curl -LsSf https://astral.sh/uv/install.sh | sh \
      || fail "uv installer failed" "install uv manually: https://docs.astral.sh/uv/"
    # the installer drops uv in ~/.local/bin, which may not be on PATH yet
    export PATH="$HOME/.local/bin:$PATH"
  fi
  have uv || fail "uv still not on PATH after install" "restart your shell, then re-run this script"
  ok "uv installed"
fi

# ---------- 3 & 4. the two CLIs ----------

install_tool() { # name, uv package spec, human label
  local bin="$1" pkg="$2" label="$3"
  if have "$bin"; then
    ok "$label present"
    return
  fi
  if [ "$CHECK_ONLY" = 1 ]; then
    warn "$label missing"
    return
  fi
  note "installing $label (uv tool install $pkg)"
  local out
  if ! out=$(uv tool install "$pkg" 2>&1); then
    printf '%s\n' "$out"
    # notebooklm-mcp-cli and notebooklm-py both ship a 'notebooklm-mcp'
    # executable, so whichever installs second collides. The skill uses 'nlm'
    # and 'notebooklm' — neither is contested — so taking the name is safe.
    if printf '%s' "$out" | grep -q "Executable already exists"; then
      warn "shim name collision with an already-installed package — retrying with --force"
      note "this overwrites the shared 'notebooklm-mcp' shim; 'nlm' and 'notebooklm' are unaffected"
      uv tool install --force "$pkg" \
        || fail "failed to install $label even with --force" "try manually: uv tool install --force $pkg"
    else
      fail "failed to install $label" "try manually: uv tool install $pkg"
    fi
  fi
  if have "$bin"; then
    ok "$label installed"
  elif [ -x "$HOME/.local/bin/$bin" ]; then
    # installed fine, just not visible — the confusing-failure case
    warn "$label installed but not on PATH"
    note "run: uv tool update-shell   then restart your shell"
    export PATH="$HOME/.local/bin:$PATH"
  else
    fail "$label installed but '$bin' not found" "try manually: uv tool install $pkg"
  fi
}

step "Checking nlm (read side — queries and source listing)"
install_tool nlm notebooklm-mcp-cli "nlm"

step "Checking notebooklm (write side — notebook creation and channel loading)"
install_tool notebooklm "notebooklm-py[browser]" "notebooklm"

# ---------- 5. chromium for playwright ----------

step "Checking Chromium (used for the notebooklm browser login)"
if [ "$CHECK_ONLY" = 1 ]; then
  note "skipped in --check mode"
elif ! have notebooklm; then
  warn "skipped — notebooklm not installed"
else
  note "this is the slowest step (~100MB download) — give it a minute"
  if uvx --from "notebooklm-py[browser]" playwright install chromium; then
    ok "Chromium ready"
  else
    warn "Chromium install failed — 'notebooklm login' will not be able to open a browser"
    note "retry: uvx --from \"notebooklm-py[browser]\" playwright install chromium"
  fi
fi

# ---------- 6. auth probe (non-fatal) ----------

step "Checking logins"

NLM_AUTH=0
NBLM_AUTH=0
have nlm        && nlm notebook list  >/dev/null 2>&1 && NLM_AUTH=1  || true
have notebooklm && notebooklm auth check >/dev/null 2>&1 && NBLM_AUTH=1 || true

status_line() { # label, installed(0/1), authed(0/1)
  local label="$1" inst="$2" auth="$3" i a
  if [ "$inst" = 1 ]; then i="${G}✓ installed${N}"; else i="${R}✗ missing${N}"; fi
  if   [ "$inst" != 1 ]; then a="${DIM}—${N}"
  elif [ "$auth" = 1 ];  then a="${G}✓ logged in${N}"
  else                        a="${Y}✗ not logged in${N}"; fi
  printf '  %-12s %-24s %s\n' "$label" "$i" "$a"
}

NLM_INST=0;  if have nlm;        then NLM_INST=1;  fi
NBLM_INST=0; if have notebooklm; then NBLM_INST=1; fi

printf '\n'
status_line "nlm"        "$NLM_INST"  "$NLM_AUTH"
status_line "notebooklm" "$NBLM_INST" "$NBLM_AUTH"

# ---------- 7. report ----------

READY=0
if [ "$NLM_INST" = 1 ] && [ "$NBLM_INST" = 1 ] && [ "$NLM_AUTH" = 1 ] && [ "$NBLM_AUTH" = 1 ]; then
  READY=1
fi

printf '\n%s──────────────────────────────────────────────%s\n' "$DIM" "$N"

if [ "$READY" = 1 ]; then
  printf '%sEverything is ready.%s\n' "$B" "$N"
  printf 'Next: ask Claude to load a channel, e.g. "load the Huberman Lab channel".\n'
else
  printf '%sNext steps — run these yourself%s:\n' "$B" "$N"
  printf '%s(the login commands open a browser for Google sign-in, so they cannot be automated)%s\n\n' "$DIM" "$N"
  if [ "$NLM_INST"  != 1 ]; then printf '  uv tool install notebooklm-mcp-cli\n'; fi
  if [ "$NBLM_INST" != 1 ]; then printf '  uv tool install "notebooklm-py[browser]"\n'; fi
  if [ "$NLM_INST"  = 1 ] && [ "$NLM_AUTH"  != 1 ]; then printf '  nlm login          # read side\n'; fi
  if [ "$NBLM_INST" = 1 ] && [ "$NBLM_AUTH" != 1 ]; then printf '  notebooklm login   # write side\n'; fi
fi

cat <<EOF

${Y}Two things that cost people the most time:${N}

  1. Both CLIs must be on the ${B}same Google account${N}. They authenticate
     independently and each defaults to whatever your browser is signed into,
     so they can silently land on different accounts.
       check:  nlm login profile list   and   notebooklm auth check

  2. The source cap is ${B}per tier${N}: free = 50, Plus/Pro = 300 per notebook.
     Loading 300 on a free account ingests ~50 and leaves the rest as red,
     empty rows. It looks like a bug; it is the tier limit.
EOF

if [ "$CHECK_ONLY" = 1 ] && [ "$READY" != 1 ]; then
  exit 2
fi
exit 0
