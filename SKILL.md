---
name: fact-graph
description: A fact-graph working memory for agentic work — replaces heavy agent front/backends with JSON files + shell. Maintains a DAG of facts (confirmed observations) and intents (units of work), queryable and writable via the `fgc` CLI, with a `dispatch` command that spawns a Sonnet agent to reason/explore against the graph. Use when the user wants to track multi-step agent work as a shared, observable graph — debugging campaigns, research reproduction, security audits — without a database or web UI. Triggers include "fact graph", "事实图", "track agent progress", "working memory for agents", "StarVoya-style graph", "commander executor without backend".
license: MIT
---

# fact-graph

A **fact graph** is shared working memory for agentic work: a DAG where
**facts** (confirmed observations) are nodes and **intents** (units of work)
are edges. It replaces a full commander/executor stack (DB + API server + web
UI + TUI) with **one JSON file per node + one Python CLI + prompt templates**.

This is a distillation of the StarVoya `Star` backend idea. StarVoya is a
~9,600-line Python/FastAPI system with a SQLite DB, dispatcher loop, container
runtime, and a TypeScript TUI. Most of that weight exists to run *outside*
Claude Code. **Inside Claude Code you already have the executor (Claude), the
scheduler (you), and the UI (this chat).** All that's missing is the durable,
queryable fact graph. That's what `fgc` provides.

## Scope — strictly per-project (IMPORTANT)

The fact graph lives **only** in the working directory, under `.fg/`. There is
no global store, no `~/.fg`, no database, no central registry:

- **Data**: `./.fg/` in whatever project you're in. `rm -rf .fg` wipes it. Move
  or delete the project directory and the graph goes with it. Nothing is ever
  written under `~` for graph data.
- **Hooks** (the always-on trigger): registered once in `~/.claude/settings.json`
  by `install.sh`. They are **dormant by design** — each turn they walk up from
  the cwd looking for a `.fg/`; if none exists they emit nothing and cost
  nothing. So a global registration activates the behavior only in projects that
  have opted in by running `fgc init`. The registration is idempotent and
  reversible (`install.sh --uninstall`).

A project that uses the graph:

```
your-project/
├── .fg/                      # ALL graph data lives here, nowhere else
│   ├── project.json          # origin, goal, status, id counters
│   ├── facts/{goal,f001,…}.json
│   ├── intents/i001.json …
│   ├── hints/
└── AGENTS.md                 # (optional) protocol for dispatched agents
```

One file per node makes the graph `git diff`-able. Writes are atomic
(`os.replace`) and guarded by `fcntl.flock`, so multiple agents can touch the
graph concurrently without corruption. Put `.fg/` in `.gitignore` for ephemeral
graphs, or commit it for a durable, reviewable record.

## When to use

- Multi-step work where you keep losing track of what's confirmed vs. tried.
- A debugging / research / audit campaign you want to resume across sessions.
- You want a record a human can read (`fgc graph`) without standing up a backend.

## What it is NOT

- Not a vector DB, not an ORM, not a server. No ports, no daemons, no deps
  beyond Python 3 stdlib.
- Not a global service. Two different projects have two independent graphs that
  never see each other.

## Layout (this skill)

```
fact-graph/
├── SKILL.md                      # you are here
├── lib/
│   ├── fg.py                     # the CLI (zero deps)
│   ├── fg-hook.py                # Claude Code hook bridge (always-on)
│   └── _settings_patch.py        # idempotent hooks installer
├── templates/
│   ├── reason.md                 # commander prompt: "what's next?"
│   ├── explore.md                # executor prompt: "do this intent"
│   └── verify.md                 # verify an executor's claimed result
├── install.sh                    # symlinks `fgc` + wires hooks
└── examples/
    └── README.md                 # a worked example
```

## Install

```bash
bash /home/S3vn/Progress/202606/newharness/factgraph/install.sh
# --cli-only    just symlink fgc, do NOT touch settings.json
# --uninstall   remove the symlink + the two hook entries
```

`fgc` uses only Python 3 stdlib — no `pip install`.

The full install also registers two **hooks** in `~/.claude/settings.json`. The
installer backs up the file first (`.json.bak`), is idempotent, and **never
removes or alters hooks you already have**:

- **SessionStart** — walks up from cwd; if a `.fg/` exists, tells the model to
  read it before working.
- **UserPromptSubmit** — walks up from cwd; if a `.fg/` exists, injects the
  current status + frontier as context before *every* turn. If no graph exists
  and the prompt looks multi-step, it suggests `fgc init`. Trivial prompts stay
  completely silent.

That registration is global, but **behavior is per-project**: no `.fg/` means
no injection, no cost, no noise. The graph itself is never stored globally.

## Core model

- **fact** — a confirmed observation or reproducible result. Immutable once
  written. Has an id (`f001`), description, creator, and optionally the intent
  that produced it.
- **intent** — a unit of work. `from` = facts it depends on; `to` = the fact it
  produced (`null` while open). An intent whose `to == "goal"` completes the
  whole project.
- **hint** — a live human message to the commander.
- **goal** — a special terminal fact created at `init` time.

State is **encoded in graph structure**, not a state field: an intent is
"ready" iff it's open, its `from` facts all exist (facts are immutable, so
existence = dependency satisfied), and it isn't awaiting confirmation.

## Command cheat-sheet

```bash
fgc init --goal "reproduce the empty-token crash"           # create .fg/
fgc setup --goal "..." --agents                             # opt-in THIS project (hooks + graph)
fgc status                                                  # project + frontier
fgc graph [--format text|json]                               # full graph
fgc frontier                                                # ready intents only
fgc pick [--claim]                                          # next intent id
fgc view [--serve]                                          # open the HTML visualization

fgc fact "<confirmed observation>" [--from-intent i003]     # add a fact
fgc intent --from f001 "reproduce with empty token"         # add work
fgc intent --from f001 "delete prod data" --confirm         # needs approval
fgc done i003 --fact "crash reproduced: see out.log"        # conclude + record
fgc complete --from f005 --note "root cause patched"        # finish project
fgc confirm i007                                            # approve gated work
fgc hint "check the middleware order"                       # message commander
fgc teardown [--purge]                                      # opt-out THIS project
```

### view — the HTML visualization

```bash
fgc view                  # write a self-contained fact-graph.html snapshot + open it
fgc view --serve          # live page that auto-refreshes every 2s as the graph changes
fgc view --out report.html
```

A dark, interactive layered DAG: facts are nodes (seed = blue, derived = teal,
goal = amber + glow), intents are edges with a status color (done = teal solid,
open = amber dashed, claimed = yellow dashed, needs-confirm = rose dashed).
Click a node or edge-label for a detail panel; drag to pan, scroll to zoom.
The static snapshot inlines the JSON so it opens from `file://` with no server;
`--serve` starts a stdlib HTTP server that polls `/__fg_graph__.json` and
redraws on change — keep it open in a window while you work.

### dispatch — spawn a Sonnet agent step

```bash
fgc dispatch reason                          # commander: read graph, propose next intents
fgc dispatch i003 --skip-permissions         # executor: work intent i003
fgc dispatch verify --intent i003            # verify i003's claimed result

fgc dispatch reason --dry-run                # just print the rendered prompt
fgc dispatch i003 --model sonnet --timeout 900
```

`dispatch reason` renders `templates/reason.md` against the graph, calls
`claude -p --output-format json`, extracts the JSON the model returns, and
**writes the new intents straight back into the graph**. `dispatch <intent>`
does the same for a single intent with `explore.md`, then records the produced
fact and links the intent. `dispatch verify` checks a concluded intent's fact.

Defaults: `--model sonnet`, `--timeout 600`. Override with `FG_MODEL` /
`FG_TIMEOUT` env vars. The executor runs in the **current working directory**
with the graph's `.fg/` on disk, so the spawned agent reads/writes the same
memory you do.

### auto — drive the whole graph to completion

```bash
fgc auto --skip-permissions                  # reason → explore (→ verify) → repeat
fgc auto --skip-permissions --verify --max-steps 10
fgc auto --dry-run                           # reason-only, no explore cost
```

`auto` is the loop you'd otherwise drive by hand: each step it runs `reason`
(propose intents / detect completion), then dispatches an executor for each
newly-ready intent, optionally verifies, and repeats. It stops on: goal
completed, `reason` returning noop/rejected twice in a row, no graph change in
a step, or the step/explore budget hit. `--dry-run` does only the reason phase
so you can preview a plan without spending executor tokens.

## The agent loop (you drive it)

```
1. fgc dispatch reason              → proposes i007, i008 into the graph
2. fgc dispatch i007 --skip-permissions   → sonnet does the work, writes f009, links i007→f009
3. fgc dispatch verify --intent i007      → confirm f009 is real
4. (repeat 1-3 until) fgc dispatch reason → returns {"complete": ...} → project done
```

Because the graph is on disk under `.fg/`, **you can step away mid-campaign and
resume** — `fgc status` tells you exactly where things stand.

## Autonomy guardrail

`fgc dispatch` spawns real `claude` subprocesses that can run shell commands and
edit files. The executor prompt instructs the agent to stay scoped to its
intent and record only confirmed observations — but like any autonomous agent
step, **review what it did before trusting the facts it wrote**. Use
`--confirm` on intents for destructive work, and `fgc dispatch verify` after
explore steps you're unsure about. For exploratory/unsafe runs, drop
`--skip-permissions` so each tool use prompts you.

### Prompt-injection surface (read this)

A dispatched executor runs with the **entire graph** — every fact, intent, and
hint `description` — interpolated into its prompt. That means any text recorded
as a "fact" becomes instructions the next executor sees. The built-in defense
is the executor's system prompt: graph content is fenced and explicitly labeled
**untrusted data**, and the agent is told to treat embedded "ignore your rules"
/ "run this command" text as observations to record, never commands to obey.
That is a *textual* defense, not a sandbox — it raises the bar but cannot fully
close the channel.

Be careful when **all three** are true at once: (1) the graph was seeded from or
fed by untrusted content (a hostile `.fg/*.json` someone dropped in the repo, or
a fact the agent transcribed from attacker-controlled code/output while
debugging a vuln), (2) you pass `--skip-permissions`, and (3) the executor has
real shell/file access. In that combination a graph field can attempt to drive
the agent. Concretely: **do not run `fgc auto --skip-permissions` (or
`dispatch <intent> --skip-permissions`) on a repo whose `.fg/` came from an
untrusted source**; prefer the default (each tool use prompts you), and read the
facts an autonomous run writes before acting on them. Treat `--skip-permissions`
as opt-in per run, never as the default.

## Customizing prompts

The templates are plain markdown with `{placeholder}` substitution. Edit
`templates/*.md` to tune the commander/executor behavior (e.g. constrain facts
to a security-finding schema, like StarVoya's `appsec` profile). Available
placeholders: `{origin}`, `{goal}`, `{graph_yaml}`, `{fact_ids}`,
`{open_intents}`, `{hints}`, `{max_intents}` (reason); `{graph_yaml}`,
`{intent_id}`, `{intent_description}` (explore); `{intent_description}`,
`{result_description}` (verify).

## Pointers into the source

- Storage + locking: `lib/fg.py` → `Store`, `atomic_write_json`, `Store.locked`
- Graph queries: `build_graph_view`, `frontier`, `is_ready`
- Renderers: `render_status`, `render_graph_text`, `render_prompt`
- Dispatch: `cmd_dispatch`, `run_claude`, `_apply_reason`, `_parse_explore_payload`
- Auto-loop driver: `cmd_auto`, `_run_reason_raw`, `_run_explore_raw`, `_run_verify_raw`
- LLM-output parsing (tolerant of surrounding prose): `extract_json_object`
- Always-on hooks: `lib/fg-hook.py` (SessionStart / UserPromptSubmit),
  `lib/_settings_patch.py` (idempotent installer)
