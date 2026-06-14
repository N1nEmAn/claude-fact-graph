#!/usr/bin/env bash
# install.sh — install the `fgc` CLI + the `fgc-setup` project skill.
#
# This installer does NOT touch ~/.claude/settings.json and does NOT register
# any global hooks. The fact-graph is strictly per-project opt-in: you opt a
# project in by running `fgc setup` (or the /fgc-setup skill) inside that
# project, which writes ./.claude/settings.json + .fg/ there.
#
# Usage:
#   bash install.sh              # install CLI + project skill (recommended)
#   bash install.sh --cli-only   # just symlink fgc, skip the skill
#   bash install.sh --uninstall  # remove the symlink + the skill
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${SCRIPT_DIR}/lib/fg.py"
mode="${1:-install}"

if ! command -v python3 >/dev/null 2>&1; then
  echo "install: python3 is required (stdlib only, no pip)." >&2
  exit 1
fi

# --- uninstall -------------------------------------------------------------
if [[ "$mode" == "--uninstall" ]]; then
  rm -f "${HOME}/.local/bin/fgc"
  echo "removed ~/.local/bin/fgc"
  if [[ -e "${HOME}/.claude/skills/fgc-setup" || -L "${HOME}/.claude/skills/fgc-setup" ]]; then
    rm -f "${HOME}/.claude/skills/fgc-setup"
    echo "removed ~/.claude/skills/fgc-setup"
  fi
  echo "uninstalled."
  echo "(Project-level .fg/ graphs and ./.claude/settings.json in your projects are untouched."
  echo " Remove them per-project with: cd <project> && fgc teardown --purge)"
  exit 0
fi

# --- install CLI -----------------------------------------------------------
if [[ ! -f "$SRC" ]]; then
  echo "install: fg.py not found at $SRC" >&2; exit 1
fi

DEST_DIR="${HOME}/.local/bin"
mkdir -p "$DEST_DIR"
if [[ -e "$DEST_DIR/fgc" || -L "$DEST_DIR/fgc" ]]; then
  rm -f "$DEST_DIR/fgc"
fi
ln -s "$SRC" "$DEST_DIR/fgc"
chmod +x "$SRC"
echo "installed: fgc -> $DEST_DIR/fgc"

case ":$PATH:" in
  *":$DEST_DIR:"*) ;;
  *) echo "install: NOTE — $DEST_DIR is not on your PATH. Add:" >&2
     echo "    export PATH=\"$DEST_DIR:\$PATH\"" >&2 ;;
esac

"$DEST_DIR/fgc" --version >/dev/null && echo "  (fgc works)"

if [[ "$mode" == "--cli-only" ]]; then
  echo "(--cli-only: skipping the /fgc-setup skill)"
  exit 0
fi

# --- install the project skill --------------------------------------------
SKILLS_DIR="${HOME}/.claude/skills"
mkdir -p "$SKILLS_DIR"
SKILL_LINK="$SKILLS_DIR/fgc-setup"
if [[ -e "$SKILL_LINK" || -L "$SKILL_LINK" ]]; then
  rm -f "$SKILL_LINK"
fi
ln -s "${SCRIPT_DIR}/skill" "$SKILL_LINK"
echo "installed: /fgc-setup skill -> $SKILL_LINK"

cat <<'NOTE'

Done. Nothing global was configured — the fact-graph is per-project opt-in.

To opt a project IN (run inside the project dir):
  fgc setup --goal "your one-line goal" --agents
  #  ↑ creates ./.fg/  +  registers hooks in ./.claude/settings.json  +  AGENTS.md

Or just invoke the skill from inside Claude Code:
  /fgc-setup <your goal>

After that, every turn in that project auto-injects the current graph state,
and you can drive it with `fgc dispatch reason` / `fgc auto`.

To opt a project OUT:
  cd <project> && fgc teardown           # removes hooks + AGENTS.md (keeps .fg/)
  cd <project> && fgc teardown --purge   # also deletes the graph data
NOTE
