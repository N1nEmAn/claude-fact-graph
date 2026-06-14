# fact-graph — worked example

A debugging campaign: the goal is to find why `python reproduce.py` segfaults.

```bash
# 0. set up a workspace
mkdir -p /tmp/fg-demo && cd /tmp/fg-demo
cat > reproduce.py <<'EOF'
import sys
print("loading module X")
# ... imagine this segfaults deep in a C extension
raise SystemExit("segfault would happen here in the real case")
EOF

# 1. create the graph
fgc init --origin "user report: segfault" --goal "find root cause of segfault in reproduce.py"

# 2. see it
fgc status
fgc graph                    # full graph as text

# 3. commander proposes the first intents (DRY RUN first to see the prompt)
fgc dispatch reason --dry-run

# 4. for real — sonnet reads the graph and writes intents into .fg/
fgc dispatch reason

# 5. work the first proposed intent (autonomous executor; prompts each tool use
#    unless you pass --skip-permissions)
fgc pick                       # -> i001
fgc dispatch i001

# 6. verify what it claimed
fgc dispatch verify --intent i001

# 7. loop: reason -> explore -> verify until the commander returns {"complete":...}
fgc dispatch reason

# 8. finish
fgc complete --from f003 --note "C extension double-free, patched in v2.1"

fgc status                     # status: completed
```

## resuming

The graph is on disk. Close the terminal, come back tomorrow:

```bash
cd /tmp/fg-demo
fgc status      # picks up exactly where you left off
fgc graph       # full history of facts + intents
```

## custom schema (e.g. a security profile)

Edit `templates/reason.md` to constrain the commander, e.g.:

> Each intent must target exactly one of: attack-surface, trust-boundary,
> payload, repro-evidence, verdict, false-positive-reason. State which.

Now the graph naturally accumulates a structured security finding instead of
free-form facts — same idea as StarVoya's `dispatch_appsec.yaml` profile, but
with no YAML, no dispatcher, and no worker pool.
