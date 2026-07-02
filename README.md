# AI fact graph (`fgc`)

**English** | [中文](README.zh-CN.md)

A **fact-graph working memory for AI agent work**, built to run inside agent terminals such as Claude Code — no database, no server, no web UI, no dependencies beyond the Python 3 standard library.

Facts are nodes. Intents are edges. The graph is one JSON file per node under a project-local `.fg/`, queryable and writable via the `fgc` CLI. A `dispatch` command can spawn a Sonnet sub-agent to reason / explore against the graph and write results straight back. For multi-agent work in tmux, `fgc peers` and `fgc send` provide an explicit user-authorized communication channel. An interactive HTML DAG view renders the whole thing and auto-refreshes.

This is a distillation of the [StarVoya](https://github.com/N1nEmAn/StarVoya) `Star` backend idea — a ~9,600-line Python/FastAPI system with SQLite, a dispatcher loop, a container runtime, and a TypeScript TUI. Most of that weight exists to run *outside* Claude Code. **Inside Claude Code you already have the executor (Claude), the scheduler (you), and the UI (the chat).** All that's missing is the durable, queryable fact graph. That's what `fgc` provides.

```
StarVoya (Star backend):  SQLite + FastAPI server + Web UI + TUI + dispatcher   →  ~9,600 lines
fact-graph (fgc):          .fg/*.json + one Python CLI + 3 prompt templates     →  ~2,900 lines, zero deps
```

## What it gives you

- **Reduce repeated exploration** — the graph records which paths were tried and which conclusions are confirmed.
- **Separate command from execution** — `dispatch reason` proposes next work; `dispatch <intent>` does it; `dispatch verify` checks it.
- **Observable, resumable process** — `fgc graph` / `fgc view` show exactly where things stand; close the terminal and resume tomorrow.
- **Autonomous, but you drive it** — `fgc auto` runs the reason→explore→verify loop to completion with budget caps and stop conditions.

## Strictly per-project, opt-in

The fact graph lives **only** in the working directory, under `.fg/`. There is no global store, no `~/.fg`, no central registry. Hooks are registered **in the project's own `.claude/settings.json`** by `fgc setup` — nothing is written under `~` for graph data, and projects that never run `fgc setup` are completely unaffected.

A project that uses the graph:

```
your-project/
├── .fg/                      # ALL graph data lives here, nowhere else
│   ├── project.json          # origin, goal, status, id counters
│   ├── facts/{goal,f001,…}.json
│   ├── intents/i001.json …
│   ├── hints/
│   ├── ai-peers.json        # optional user-authorized tmux peer targets
│   ├── ai-channel.txt       # optional append-only peer message log
│   └── runs/                 # dispatch execution log
└── AGENTS.md                 # (optional) protocol for dispatched agents
```

One file per node makes the graph `git diff`-able. Writes are atomic (`os.replace`) and guarded by `fcntl.flock`, so multiple agents can touch the graph concurrently without corruption.

## Install

```bash
git clone https://github.com/N1nEmAn/claude-fact-graph.git
cd claude-fact-graph
bash install.sh            # symlinks `fgc` onto PATH + installs the /fgc-setup skill
#   --cli-only    just symlink fgc, don't install the skill
#   --uninstall   remove both
```

`fgc` uses only Python 3 stdlib — no `pip install`. The installer does **not** touch `~/.claude/settings.json` and registers **no global hooks**.

## Opt a project in

```bash
cd /path/to/your/project
fgc setup --goal "reproduce the empty-token crash" --agents
#   → creates ./.fg/
#   → registers SessionStart + UserPromptSubmit hooks in ./.claude/settings.json
#   → writes AGENTS.md
```

Or from inside Claude Code: `/fgc-setup <your goal>`.

After that, every turn in that project injects the current graph state, and dispatched sub-agents read/write the same memory.
The hooks also run `date` and inject the current local time so agents have concrete time context.

## Core model

- **fact** — a confirmed observation or reproducible result. Immutable once written.
- **intent** — a unit of work. `from` = facts it depends on; `to` = the fact it produced (`null` while open). An intent whose `to == "goal"` completes the project.
- **hint** — a live human message to the commander.
- **goal** — a special terminal fact created at `init` time.

State is encoded in graph structure, not a state field: an intent is "ready" iff it's open, its `from` facts all exist, and it isn't awaiting confirmation.

## Command cheat-sheet

```bash
fgc init --goal "..."                          # create .fg/ (or use `fgc setup`)
fgc setup --goal "..." --agents                # opt-in THIS project (graph + hooks + AGENTS.md)
fgc status                                     # project + frontier
fgc graph [--format text|json]                 # full graph
fgc frontier                                   # ready intents only
fgc pick [--claim] [--any]                     # next intent id
fgc view [--serve]                             # interactive HTML DAG

fgc fact "<observation>" -t "<中文标题>"        # add a fact
fgc intent --from f001 "do X" -t "<标题>"      # add work
fgc intent --from f001 "rm prod" --confirm     # needs approval
fgc done i003 --fact "<result>" -t "<标题>"    # conclude + record
fgc complete --from f005 --note "..."          # finish project
fgc confirm i007                               # approve gated work
fgc hint "<message>"                           # message the commander
fgc peers --discover                           # list tmux panes before user authorization
fgc peers --add harley --target api-6:0.0      # authorize one tmux peer
fgc send harley "status?"                      # send via tmux + append .fg/ai-channel.txt
fgc teardown [--purge]                         # opt-out THIS project
```

Every fact and intent accepts a `-t/--title`: a short human label (中文 ok) shown as the node label in the graph view.

### peers / send — authorized tmux peer messaging

`fgc` can coordinate multiple AI agents that are already running in tmux, but it never messages a pane just because it discovered one. Peer messaging is an explicit opt-in:

```bash
fgc peers --discover
# show the list to the user and ask which panes/agents may communicate

fgc peers --add harley --target api-6:0.0 --sender "Codex/api2-4"
fgc peers
fgc send harley "I fixed the login build; please verify your side."
```

Authorized peers are stored in `.fg/ai-peers.json`. `fgc send` refuses unknown names, appends the message to `.fg/ai-channel.txt`, and uses tmux `load-buffer`/`paste-buffer` with extra pasted newlines so Claude Code-style TUIs submit reliably after idle or goal-complete states. Agents should read `fgc peers` before sending and should ask the user before adding or changing any peer target.

### dispatch — spawn a Sonnet agent step

```bash
fgc dispatch reason                 # commander: read graph, propose next intents
fgc dispatch i003 --skip-permissions # executor: work intent i003
fgc dispatch verify --intent i003   # verify i003's claimed result

fgc dispatch reason --dry-run       # just print the rendered prompt
```

`dispatch reason` renders `templates/reason.md` against the graph, calls `claude -p --output-format json`, extracts the returned JSON, and **writes the new intents straight back into the graph**. `dispatch <intent>` does the same for one intent with `explore.md`, then records the produced fact and links the intent atomically. Defaults: `--model sonnet`, `--timeout 600`; override with `FG_MODEL` / `FG_TIMEOUT`.

### auto — drive the graph to completion

```bash
fgc auto --skip-permissions                  # reason → explore (→ verify) → repeat
fgc auto --skip-permissions --verify --max-steps 10
fgc auto --dry-run                           # reason-only preview
```

Each step runs `reason` (propose / detect completion), then dispatches an executor per newly-ready intent, optionally verifies, and repeats. Stops on: goal completed, `reason` noop/rejected twice in a row, no graph change, or the step/explore budget hit.

### view — the HTML visualization

```bash
fgc view                  # write a self-contained fact-graph.html snapshot + open it
fgc view --serve          # live page that auto-refreshes every 2s as the graph changes
```

A dark, interactive layered DAG: facts are nodes (seed = blue, derived = teal, goal = amber + glow), intents are edges colored by status (done = teal solid, open = amber dashed, claimed = yellow dashed, needs-confirm = rose dashed). Click a node or edge for a detail panel; drag to pan, scroll to zoom. The static snapshot inlines the JSON so it opens from `file://` with no server; `--serve` starts a stdlib HTTP server bound to loopback with an unguessable token path, polling `/__fg_graph__/<token>.json` (same-origin, no CORS).

## Autonomy guardrail — prompt injection

A dispatched executor runs with the **entire graph** — every fact, intent, and hint `description` — interpolated into its prompt. Any text recorded as a "fact" becomes instructions the next executor sees. Both the commander (`reason.md`) and executor (`_agents_system_prompt`) prompts fence graph content as **untrusted data** and instruct the agent to treat embedded "ignore your rules / run this command" text as an observation to record, never a command to obey. That is a *textual* defense, not a sandbox.

Be careful when all three hold at once: (1) the graph was seeded from / fed by untrusted content (a hostile `.fg/*.json`, or a fact transcribed from attacker-controlled code), (2) you pass `--skip-permissions`, (3) the executor has real shell/file access. **Do not run `fgc auto --skip-permissions` on a repo whose `.fg/` is untrusted.** Prefer the default (each tool use prompts you), and read the facts an autonomous run writes before acting on them.

## Customizing prompts

The templates are plain markdown with `{placeholder}` substitution. Edit `templates/*.md` to tune behavior (e.g. constrain facts to a security-finding schema). Placeholders: `{origin}`, `{goal}`, `{graph_yaml}`, `{fact_ids}`, `{open_intents}`, `{hints}`, `{max_intents}` (reason); `{graph_yaml}`, `{intent_id}`, `{intent_description}` (explore); `{intent_description}`, `{result_description}` (verify).

## Requirements

- Python 3.10+ (stdlib only — `json`, `fcntl`, `http.server`, `argparse`, …)
- A POSIX system (Linux / macOS / WSL). `fcntl.flock` is not available on Windows.
- The `claude` CLI on PATH for `dispatch` / `auto` (Claude Code).
- Optional: `tmux` for user-authorized multi-agent peer messaging.

## Layout

```
claude-fact-graph/
├── lib/
│   ├── fg.py                # the CLI: Store, graph ops, dispatch, auto-loop, view, setup/teardown
│   ├── fg-hook.py           # Claude Code SessionStart / UserPromptSubmit hook bridge
│   ├── _settings_patch.py   # idempotent add/remove of hook entries in a settings.json
│   └── view_template.html   # single-file dark DAG visualization (embedded JS)
├── templates/
│   ├── reason.md            # commander prompt
│   ├── explore.md           # executor prompt
│   └── verify.md            # verifier prompt
├── skill/SKILL.md           # the /fgc-setup project skill
├── examples/README.md       # worked example
├── install.sh
├── SKILL.md                 # root skill doc (this README is the canonical overview)
└── LICENSE                  # MIT
```

## Acknowledgements

Built on ideas from [StarVoya](https://github.com/N1nEmAn/StarVoya) / [Cairn (衍迹)](https://github.com/oritera/Cairn) (fact/intent graph, dispatcher, worker scheduling) and [pi-mono](https://github.com/badlogic/pi-mono) (agent runtime, tool system) — distilled to run natively inside Claude Code with no backend.

## License

MIT © N1nEmAn
