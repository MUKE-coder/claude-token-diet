# token-diet 🥗

**Make Claude Code cheap on huge codebases.** Install this skill, open Claude Code in your big repo, say *"run token-diet"* — the agent measures your repo, configures everything, verifies it, and writes a report. It only stops to ask before installing third-party tools, sending code to external services, or rewriting your existing instructions.

## What it does

| Phase | The agent… |
|---|---|
| 0. Preflight | Detects languages, test runners, generated/vendored dirs, installed tools. Asks one batch of questions. |
| 1. Baseline | Writes `.claude/token-baseline.md` (repo size, biggest files, always-loaded instruction tokens) + 3 benchmark tasks. |
| 2. Native config | Adds `Read` deny rules for generated/vendored/lock/minified files, slims root `CLAUDE.md` to < 200 lines, splits area rules into per-directory `CLAUDE.md` and path-scoped `.claude/rules`, adds an exploration policy and compaction instructions. |
| 3. Code intelligence | Installs the official LSP plugin(s) so Claude jumps to definitions instead of grepping and reading. |
| 4. Retrieval layer | Installs **one** of Serena / code-review-graph / claude-context (your choice, with a recommendation). |
| 5. Hooks | **read-guard** blocks whole-file reads of huge files and returns an outline; **test filter** turns 5,000-line test logs into failures + summary (exit code kept). Self-tested. |
| 6. Subagent & map | Creates a Haiku `scout` subagent for exploration and a `codebase-map` skill so Claude stops re-exploring. |
| 7. Verify & report | Runs checks, re-measures, writes `.claude/token-diet/REPORT.md` with before/after and a next-session checklist. |

Everything it edits is backed up to `.claude/token-diet/backup/`, and runs are resumable via `.claude/token-diet/state.json`.

## Install

**Option A — Claude Code plugin (recommended)**
```text
/plugin marketplace add MUKE-coder/claude-token-diet
/plugin install token-diet@token-diet
```

**Option B — skills CLI (works with many agents)**
```bash
npx skills add MUKE-coder/claude-token-diet
```

**Option C — manual**
```bash
git clone https://github.com/MUKE-coder/claude-token-diet
cd claude-token-diet && ./install.sh          # personal, all projects
# or, from inside your big repo:  /path/to/claude-token-diet/install.sh --project
```

## Use

```bash
cd /path/to/your/huge-repo
claude
> run token-diet
```
(or `/token-diet`). Then **restart Claude Code** so the new hooks, settings and tools load, and follow the checklist in `.claude/token-diet/REPORT.md`.

## Requirements

- Claude Code (recent version), `git`, **Python 3** (scripts and hooks are stdlib-only)
- Optional, installed only with your approval: language servers, `uv`/`uvx` (Serena), `pipx` (code-review-graph), Node (claude-context), RTK

## Safety notes

- Settings are merged, never overwritten; invalid JSON aborts with no changes.
- The test-output hook auto-approves only a *pure* test command (e.g. `npm test`, `pytest -x`, `cd api && go test ./...`). Anything chained, piped or redirected is untouched. Opt out per command with `TOKEN_DIET_RAW=1`.
- The read-guard fails open: if anything goes wrong, the read is allowed.
- claude-context sends code chunks to an embedding provider — the skill asks for explicit consent.
- Savings numbers from third-party tools are their authors' benchmarks. The skill makes you re-run your own benchmark tasks and remove anything that doesn't help.

## Undo

Say *"undo token-diet"*: the agent restores backups, removes the hooks and uninstalls the tools it added.

## Repo layout

```
.claude-plugin/          plugin + marketplace manifests
skills/token-diet/
  SKILL.md               the workflow the agent follows
  scripts/               detect, baseline, merge_settings, hooks, tests, verify
  references/            phase details loaded on demand
  templates/             scout agent, codebase-map skill, CLAUDE.md snippet, rules, report
docs/PLAYBOOK.md         the human-readable guide this skill automates
install.sh               manual installer
```

## Credits / prior art

Built on Anthropic's Claude Code docs (costs, large codebases, memory, skills, hooks) and ideas from Serena, code-review-graph, claude-context (Zilliz), RTK, token-economy-kit and caveman.

MIT licensed.
