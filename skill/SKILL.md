---
name: fgc-setup
description: Opt-in the CURRENT project to the fact-graph working memory. Creates the local .fg/ graph, registers the SessionStart + UserPromptSubmit hooks in this project's .claude/settings.json (NOT global — other projects are untouched), and writes AGENTS.md. After setup, every turn in this project auto-injects the current graph state so Claude always knows what's confirmed vs. tried, and sub-agents (fgc dispatch) can read/write the same graph. Use when the user says "enable fact-graph here", "在这个项目用 fgc", "setup the fact graph", "init the working memory for this project", or when starting a multi-step debugging/research/audit campaign that should be tracked and resumable. This is the per-project initializer the install.sh skill exposes as a slash command.
license: MIT
---

# fgc-setup

Per-project initializer for the **fact-graph** working memory. This is the
opt-in switch: until you run it in a project, the fact-graph does nothing
there. After you run it, that one project auto-reads and auto-maintains its
graph on every turn.

This replaces the StarVoya `Star` backend's "create a project + start the
dispatcher" step, but with zero servers — it just drops a local `.fg/` and
writes the two hook entries into **this project's** `.claude/settings.json`.

## What it does

Run inside the target project directory. Exactly three things, all local:

1. **Creates the graph** at `./.fg/` (unless one already exists):
   `project.json`, `facts/goal.json`, and the `intents/` `hints/` `runs/` dirs.
2. **Registers hooks** in `./.claude/settings.json` — `SessionStart` and
   `UserPromptSubmit`, both pointing at `fg-hook.py`. These inject the current
   graph state into every turn so the model always knows the frontier. This is
   a **project-level** settings file; the user-level `~/.claude/settings.json`
   and every other project are completely untouched.
3. **(optional) Writes `AGENTS.md`** so dispatched sub-agents learn the
   fact-graph protocol (`fgc fact`, `fgc done`, etc.).

No daemons, no ports, no database. `rm -rf .fg .claude` undoes everything.

## How to run it

From the shell (after `bash install.sh`):

```bash
cd /path/to/your/project
fgc setup --goal "reproduce the empty-token crash" --agents
```

Or, since this is a skill, the user can just type `/fgc-setup <goal>` inside
Claude Code and Claude will run the equivalent commands.

## After setup

- The model is reminded each session + each turn to read/maintain the graph.
- Drive it with `fgc dispatch reason` (commander proposes next work),
  `fgc dispatch <intent-id> --skip-permissions` (executor does the work),
  `fgc dispatch verify --intent <id>` (verify a result), or
  `fgc auto --skip-permissions` (full loop to completion).
- See state anytime: `fgc status`, `fgc graph`.

## Undo

```bash
fgc teardown            # removes hooks + AGENTS.md from THIS project, keeps .fg/
fgc teardown --purge    # also deletes the graph data
```

`install.sh --uninstall` removes the `fgc` command and this skill globally, but
never touches project-level `.fg/` or `.claude/` — those are per-project and
must be removed per-project with `teardown`.

## Autonomy guardrail (prompt injection)

A dispatched executor (`fgc dispatch <intent>`, `fgc auto`) runs the whole graph
— every fact/intent/hint text — interpolated into its prompt. So text recorded
as a "fact" becomes instructions the next executor sees. The executor system
prompt fences graph content as **untrusted data** and tells the agent to treat
embedded "ignore your rules / run this command" text as an observation to
record, not a command to obey. That is a textual defense, not a sandbox.

Dangerous combination: a graph fed by **untrusted** content (a hostile
`.fg/*.json` in the repo, or facts transcribed from attacker-controlled
code/output) **plus** `--skip-permissions` **plus** real shell/file access. In
that case a graph field can attempt to drive the agent. **Do not run
`fgc auto --skip-permissions` on a repo whose `.fg/` is untrusted** — prefer the
default (each tool use prompts you), and read the facts an autonomous run
writes before acting on them. Treat `--skip-permissions` as opt-in per run.

## Where things live (IMPORTANT — nothing global)

- `./.fg/` — all graph data. Move/delete the project, the graph goes with it.
- `./.claude/settings.json` — the two hook entries, project-scoped.
- `./AGENTS.md` — sub-agent protocol (optional).
- `~/.local/bin/fgc` — the CLI (one symlink).
- `~/.claude/skills/fgc-setup` — this skill (one symlink).

There is no `~/.fg`, no global hook registration, no shared state between
projects. Two opted-in projects have two independent graphs.
