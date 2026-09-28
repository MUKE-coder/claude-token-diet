# Token Efficiency Playbook for Very Large Codebases

> **Audience:** Claude Code (the agent) and the developer who owns this repo.
> **Goal:** Make small changes in a 1,000s-of-files / 1M+ LOC codebase cost small numbers of tokens.
> **How to use:** Give this file to Claude Code and say:
> *"Read TOKEN_EFFICIENCY_PLAYBOOK.md. Execute Phase 0, report the baseline, then implement Phases 1–5 one at a time, asking me before each phase that installs third‑party software."*

---

## Why tokens explode in big repos (the mental model)

Every request re-sends: system prompt + tool definitions + **all CLAUDE.md / rules loaded so far** + **the whole conversation, including every file read and command output**. So cost is driven by five things, and each phase below attacks one:

| Leak | Typical cause | Fix (phase) |
|---|---|---|
| Always-loaded instructions | Giant root CLAUDE.md | Phase 1 |
| Reading the wrong / irrelevant files | Generated code, vendored SDKs, grep → read 10 candidate files | Phases 1–2 |
| Reading whole files to find one function | Built-in Read on 3,000-line files | Phases 2–3 |
| Noisy command output | Full test logs, `git log`, build output | Phase 3 |
| Exploration living in the main context forever | Investigating in the main thread | Phases 4–5 |
| Long-lived sessions | Never `/clear`; idle past cache TTL | Phase 6 (habits) |

**Rule for the agent:** do not stack every tool. Pick ONE retrieval layer in Phase 2. Overlapping MCP servers add tool definitions and cause duplicated reads.

---

## Phase 0 — Measure the baseline (do this first, no changes)

1. Run `/context` and record: total tokens used at session start, size of *Memory files*, MCP tools, skills.
2. Run `/usage` and note the plan-usage breakdown (skills, subagents, MCP servers, behavior flags like "long context" or "cache misses").
3. Run `/insights` to get the HTML report of friction patterns (written to `~/.claude/usage-data/report.html`).
4. Measure the repo:
   ```bash
   git ls-files | wc -l
   git ls-files | xargs wc -c 2>/dev/null | tail -1        # total bytes ≈ tokens × 4
   git ls-files | xargs wc -l 2>/dev/null | sort -rn | head -40   # biggest files
   wc -l CLAUDE.md $(find . -name CLAUDE.md -not -path '*/node_modules/*') 2>/dev/null
   ```
5. Pick **3 representative small tasks** from recent history (e.g. "add a field to X", "fix bug in Y"). These become the benchmark. After each phase, re-run one in a fresh session and compare `/usage` numbers.
6. Write findings to `.claude/token-baseline.md` (commit it).

**Deliverable:** baseline table (startup tokens, memory-file tokens, biggest files, top-level directories with file counts).

---

## Phase 1 — Native Claude Code configuration (zero dependencies, biggest safe win)

All of these are official Claude Code features. Implement all of them.

### 1.1 Block generated, vendored and build files

`.gitignore`'d paths are already excluded from Claude's searches. For **checked-in** noise (generated clients, vendored SDKs, fixtures, snapshots, minified bundles, lockfiles), add Read deny rules.

> Note: `.claudeignore` is a community convention, **not** an official feature. Use `permissions.deny`.

Create/merge into `.claude/settings.json` at the repo root:

```json
{
  "permissions": {
    "deny": [
      "Read(./**/dist/**/*)",
      "Read(./**/build/**/*)",
      "Read(./**/vendor/**/*)",
      "Read(./**/generated/**/*)",
      "Read(./**/*.generated.*)",
      "Read(./**/*.min.js)",
      "Read(./**/*.map)",
      "Read(./**/__snapshots__/**/*)",
      "Read(./**/fixtures/**/*)",
      "Read(./package-lock.json)",
      "Read(./yarn.lock)",
      "Read(./pnpm-lock.yaml)"
    ]
  }
}
```

**Agent task:** inspect the repo (Phase 0 output) and tailor this list to the actual generated/vendored directories. Directory patterns end in `/**/*` so Claude can still `ls` the directory. Caveat: a raw `grep -r` / `find` in Bash over those dirs still shows content — prefer the built-in Grep/Glob tools.

### 1.2 Slim the root CLAUDE.md to < 200 lines

The root CLAUDE.md is loaded into **every** request. Keep only what applies everywhere:
- One-paragraph project description
- How to build / test / lint (exact commands, including how to run a **single** test)
- Repo-wide conventions (commit format, "never edit generated files, run codegen")
- A pointer: "For the module map, use the `codebase-map` skill."
- The exploration policy (see 1.6)

Move everything else out (see 1.3–1.5). Note: `@path` imports do **not** save tokens — imported files load at startup anyway. Only per-directory files, path-scoped rules and skills load on demand.

### 1.3 Per-directory CLAUDE.md files (load on demand)

Subdirectory CLAUDE.md files load only when Claude reads a file in that directory. For each major subsystem (e.g. `src/api/`, `src/db/`, `packages/web/`), create a short CLAUDE.md (10–40 lines) with that area's stack, conventions, and gotchas.

**Agent task:** propose the split (list of directories + what moves where), get approval, then create them.

### 1.4 Path-scoped rules for cross-cutting conventions

For rules that apply to scattered files (all migrations, all tests, all `.proto`), use `.claude/rules/*.md` with `paths:` frontmatter so they load only when a matching file is touched:

```markdown
---
paths:
  - "**/migrations/**"
---
Never edit a merged migration. Create a new one with `make migration name=...`.
```

Rules **without** `paths:` load every session — avoid that for anything non-universal.

### 1.5 Exclude CLAUDE.md files for areas you never work in

In `.claude/settings.local.json` (personal, gitignored):

```json
{
  "claudeMdExcludes": [
    "**/legacy/**",
    "**/packages/other-team-*/**"
  ]
}
```

### 1.6 Exploration policy (paste into root CLAUDE.md, ~8 lines)

```markdown
## Exploration policy (token budget)
- Locate before reading: use LSP/symbol tools or Grep with narrow globs first; never read a file "to see what's in it".
- Read slices, not files: for files > 300 lines, Read with offset/limit around the match.
- Never read generated, vendored, lock, or snapshot files.
- Questions needing > 5 files: delegate to the `scout` subagent and ask for `path:line` conclusions only.
- Filter command output at the source: single test, `--quiet`, `| tail -50`, `git log --oneline -20`.
- Don't re-read a file you already read this session unless it changed.
- Answers: lead with the change; no restating the plan or the diff.
```

### 1.7 Compaction instructions

Add to root CLAUDE.md:

```markdown
# Compact instructions
When compacting, keep: the current task goal, files changed and why, failing test names, decisions made. Drop: file contents already read, exploration dead ends, full command output.
```

### 1.8 Start Claude from the subsystem, not the root (developer habit + docs)

Launching `claude` inside `src/billing/` loads only that directory's CLAUDE.md plus ancestors. Use `claude --add-dir ../shared` when a task needs a sibling. Document this in the root README/CLAUDE.md.

**Checkpoint:** re-run `/context` in a fresh session. Memory-file tokens should drop substantially. Record in `.claude/token-baseline.md`.

---

## Phase 2 — Replace "grep + read whole files" with precise retrieval

Choose based on the codebase. **Default recommendation: 2.1 always, plus exactly one of 2.2 / 2.3 / 2.4.** Ask the developer before installing anything third-party.

### 2.1 Official code-intelligence (LSP) plugin — do this first

Gives go-to-definition / find-references / type errors via the language server, replacing grep-then-read-candidates.

```text
/plugin marketplace add anthropics/claude-plugins-official
/plugin install typescript-lsp@claude-plugins-official     # or python / go / rust equivalents
```

Requires the language server binary installed locally (e.g. `typescript-language-server`, `pyright`, `gopls`, `rust-analyzer`). For a team, add it to `enabledPlugins` in `.claude/settings.json`.

### 2.2 Option A — Serena (symbol-level read AND edit, local, no index service)

Best for: large, strongly-typed / polyglot codebases where edits are "change this function".
Tools: `find_symbol`, `get_symbols_overview`, `find_referencing_symbols`, `replace_symbol_body`, `insert_after_symbol`.

```bash
claude mcp add --scope user serena -- \
  uvx --from git+https://github.com/oraios/serena serena start-mcp-server \
  --context claude-code --project-from-cwd
```

Caveats: first run indexes the project (minutes on big repos); savings show up on large repos and long sessions, and some users report *higher* usage on small tasks. Benchmark with your Phase 0 tasks before keeping it. Install from the official repo (github.com/oraios/serena), not random marketplace forks.

### 2.3 Option B — Code knowledge graph (code-review-graph / codegraph)

Best for: "what calls this / what breaks if I change this" questions and PR review. Local SQLite graph built with Tree-sitter, incremental updates.

```bash
pipx install code-review-graph
code-review-graph install --platform claude-code
code-review-graph build          # first full parse
code-review-graph watch &        # or run `update` in a post-commit hook
```

Usage rule to add to CLAUDE.md: *"Narrow scope with the graph (`get_minimal_context`, `query_graph_tool` callers_of/tests_for, `get_impact_radius_tool`), then read only the returned source. Never edit from graph output alone."*

### 2.4 Option C — Semantic search index (zilliz claude-context)

Best for: fuzzy "where do we handle X?" questions in huge repos with inconsistent naming. Hybrid BM25 + vector search, AST chunking, incremental re-index. Vendor benchmark: ~40% fewer tokens at equal retrieval quality.

```bash
claude mcp add claude-context \
  -e OPENAI_API_KEY=... -e MILVUS_TOKEN=... \
  -- npx @zilliz/claude-context-mcp@latest
```

Caveats: needs an embedding provider and a vector DB (Zilliz Cloud or self-hosted Milvus; Ollama for local embeddings). **Check with the developer about sending code embeddings to third-party services.** Local-only alternatives: grepai, semantic-cache-mcp.

### Decision table

| Codebase / pain | Pick |
|---|---|
| Typed language, most tasks are "edit function X" | 2.1 + Serena |
| Lots of "what's the blast radius?" / reviews | 2.1 + code-review-graph |
| Huge, inconsistent naming, lots of "where is…?" | 2.1 + claude-context |
| Untyped / unusual language, no LSP | code-review-graph or claude-context |

After installing, run `/mcp` and disable any MCP server not used this week. Prefer CLI tools (`gh`, `aws`, etc.) over MCP servers where both exist.

---

## Phase 3 — Hooks that stop waste mechanically

CLAUDE.md rules get forgotten under pressure; hooks are enforced. Implement 3.1 and 3.2; 3.3 is optional.

### 3.1 Read-guard hook: block whole-file reads of huge files

Create `.claude/hooks/read-guard.sh` (requires `jq`):

```bash
#!/usr/bin/env bash
# Denies full-file Reads of files over a token budget; returns an outline instead.
BUDGET_TOKENS="${READ_GUARD_BUDGET:-8000}"
input="$(cat)"
file="$(echo "$input" | jq -r '.tool_input.file_path // empty')"
limit="$(echo "$input" | jq -r '.tool_input.limit // empty')"

# Allow sliced reads and missing/non-regular files
[[ -z "$file" || -n "$limit" || ! -f "$file" ]] && { echo '{}'; exit 0; }

bytes=$(wc -c < "$file")
est=$(( bytes / 4 ))
if (( est <= BUDGET_TOKENS )); then echo '{}'; exit 0; fi

lines=$(wc -l < "$file")
outline=$(grep -nE '^\s*(export\s+)?(async\s+)?(def|class|function|func|fn|interface|type|struct|enum|impl|public|private|protected)\b' "$file" \
          | head -80 | cut -c1-140)

reason="BLOCKED: $file is ~${est} tokens (${lines} lines), over the ${BUDGET_TOKENS}-token read budget.
Read only the relevant slice using offset/limit, or use symbol tools (LSP/Serena/graph).
Outline (line:definition):
${outline}"

jq -n --arg r "$reason" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
```

### 3.2 Test-output filter hook

Create `.claude/hooks/filter-test-output.sh` (adapt the regex to this repo's test runners):

```bash
#!/usr/bin/env bash
input="$(cat)"
cmd="$(echo "$input" | jq -r '.tool_input.command')"
if [[ "$cmd" =~ ^(npm\ test|pnpm\ test|yarn\ test|pytest|go\ test|cargo\ test|mvn\ test|gradle\ test) ]]; then
  filtered="$cmd 2>&1 | grep -A 8 -E '(FAIL|ERROR|error:|panicked|Traceback|AssertionError)' | head -150; exit \${PIPESTATUS[0]}"
  echo "$input" | jq --arg f "$filtered" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow",updatedInput:(.tool_input + {command:$f})}}'
else
  echo '{}'
fi
```

(Agent: verify the exit-code passthrough works in this shell; if tests pass the grep output will be empty — make sure a "0 failures" line or the exit code is still visible.)

### 3.3 Optional: RTK (Rust Token Killer) for all common CLI output

Transparent Bash hook that rewrites `git status`, `ls`, test runners, builds, etc. into compressed output. Claims 60–90% reduction on those commands. Does **not** affect built-in Read/Grep/Glob.

```bash
# Install from https://github.com/rtk-ai/rtk (beware: crates.io "rtk" is a DIFFERENT project)
rtk gain            # verify it's Token Killer
rtk init -g         # installs hook + slim RTK.md
rtk discover        # shows which past commands would have been compressed
```

If RTK is installed, 3.2 may be redundant — keep whichever tests better.

### Register the hooks

Merge into `.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Read", "hooks": [{ "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/read-guard.sh" }] },
      { "matcher": "Bash", "hooks": [{ "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/filter-test-output.sh" }] }
    ]
  }
}
```

Then: `chmod +x .claude/hooks/*.sh`, run `/hooks` to confirm, and test by asking Claude to read the largest file from Phase 0 (should be blocked with an outline).

---

## Phase 4 — Skills: pre-computed knowledge instead of re-exploration

Skills load only their name + description until invoked, so they're the right home for anything longer than a few lines.

### 4.1 `codebase-map` skill (highest value)

Have Claude do ONE expensive exploration, then never pay for it again.

**Agent task:**
1. Using the `scout` subagent (Phase 5), produce `.claude/skills/codebase-map/MAP.md`:
   - Each top-level module/package: one-line purpose, key entry files, owns which domain concepts, depends on which modules.
   - "Where to look for…" table: auth, DB access, routing, config, feature flags, background jobs, error handling, logging, tests helpers.
   - Naming conventions and where generated code comes from.
   - Keep under ~400 lines. Paths, not prose.
2. Create `.claude/skills/codebase-map/SKILL.md`:

```markdown
---
name: codebase-map
description: Architecture and "where is X" map of this repository. Use before exploring unfamiliar code or when locating where a feature, concept, or layer lives.
---
Read MAP.md in this skill's directory (${CLAUDE_SKILL_DIR}/MAP.md) and use it to jump directly to the right files. Do not re-explore areas the map covers. If the map is wrong or stale for the area you touched, fix the relevant line in MAP.md at the end of the task.
```

3. Add a monthly (or per-release) reminder to regenerate it.

### 4.2 Per-area workflow skills

Move procedures out of CLAUDE.md into skills scoped by location or `paths:` — e.g. `src/api/.claude/skills/api-testing/`, a `db-migrations` skill with `paths: ["**/migrations/**"]`, a `release` skill. Keep descriptions short and keyword-first so they're still matched when many skills exist.

### 4.3 Optional: output-brevity skill (caveman)

Community skill that forces terse replies; claims ~65% average **output**-token reduction (input unaffected). Install only if the developer wants terse chat style:

```text
claude plugin marketplace add JuliusBrussee/caveman && claude plugin install caveman@caveman
```

A lighter alternative is the last line of the exploration policy in 1.6.

---

## Phase 5 — Subagents and model routing

### 5.1 `scout` subagent: exploration off the main context

Create `.claude/agents/scout.md`:

```markdown
---
name: scout
description: Read-only codebase investigator. Use for any question that needs more than ~5 files read, tracing a flow across modules, or finding all usages of something. Returns conclusions, not file contents.
tools: Read, Grep, Glob, Bash
model: haiku
---
You investigate a codebase and report back concisely.
- Use the codebase-map skill and LSP/symbol tools first; read slices, not whole files.
- Never modify files.
- Return at most ~40 lines: a direct answer, then a list of `path:line — why it matters`.
- Do not paste code blocks longer than 10 lines. Do not include exploration narrative.
```

The verbose reading stays in the subagent's context; only the summary returns to the main conversation.

### 5.2 Delegate other verbose work

Running a full test suite, reading logs, fetching docs → delegate to a subagent that returns only failures / the relevant facts.

### 5.3 Model and effort

- Default to Sonnet for routine edits; switch to Opus (`/model`) only for architecture or hard multi-step reasoning.
- Lower thinking effort (`/effort`) for trivial edits.
- Keep subagents on Haiku unless they fail.
- Avoid agent teams for small changes (each teammate has its own full context).

---

## Phase 6 — Session habits (for the developer; agent should remind when relevant)

1. **One task per session.** `/clear` between unrelated tasks (use `/rename` first so you can `/resume`). `/clear` is free; `/compact` itself costs a large request.
2. **Specific prompts.** "Add `email_verified` to `User` in `src/models/user.py` and its serializer" beats "add email verification" — vague prompts trigger broad scanning. Mention file paths or symbols when you know them.
3. **Plan mode (Shift+Tab) for anything multi-file.** Plan file survives compaction.
4. **Stop early.** Press Esc as soon as Claude heads the wrong way; `/rewind` rather than arguing it back.
5. **Mind the cache.** Returning to a huge session after the cache TTL expires re-processes the whole context — for big sessions after a long break, start fresh or resume from summary.
6. **Start `claude` inside the subsystem directory** when the task is local to it.
7. **Watch `/context` via the status line** and act before auto-compact kicks in.
8. **Custom compaction:** `/compact keep only the plan, changed files, and failing tests`.

---

## Phase 7 — Verify, iterate, keep it healthy

1. Re-run the 3 benchmark tasks from Phase 0 in fresh sessions. Record startup tokens, total tokens, number of Read calls, and result quality in `.claude/token-baseline.md`.
2. If a tool (Serena / graph / semantic index / RTK) didn't reduce tokens for these tasks, **remove it** — extra MCP tools and hooks have their own overhead.
3. Check `/usage` attribution weekly for a heavy MCP server, skill, or subagent.
4. Revisit CLAUDE.md files after major model releases; delete rules that worked around old model limitations.
5. Optional: a `Stop` hook that reviews the session transcript and proposes CLAUDE.md / MAP.md updates.

---

## Implementation checklist (agent: tick these off and report)

- [ ] Phase 0 baseline recorded in `.claude/token-baseline.md`
- [ ] `permissions.deny` Read rules tailored to this repo
- [ ] Root CLAUDE.md < 200 lines, with exploration policy + compact instructions
- [ ] Per-directory CLAUDE.md files for major subsystems
- [ ] `.claude/rules/*.md` with `paths:` for cross-cutting conventions
- [ ] `claudeMdExcludes` for never-touched areas (local settings)
- [ ] LSP code-intelligence plugin installed and verified
- [ ] ONE retrieval layer chosen (Serena / code-review-graph / claude-context) — with developer approval
- [ ] read-guard hook installed and tested on the largest file
- [ ] test-output filter hook (or RTK) installed and tested
- [ ] `codebase-map` skill + MAP.md generated
- [ ] `scout` subagent created (Haiku)
- [ ] Unused MCP servers disabled
- [ ] Benchmarks re-run and compared to baseline

## Sources (for the developer)

- Anthropic — Manage costs effectively: https://code.claude.com/docs/en/costs
- Anthropic — Set up Claude Code in a monorepo or large codebase: https://code.claude.com/docs/en/large-codebases
- Anthropic — Memory / CLAUDE.md & path-scoped rules: https://code.claude.com/docs/en/memory
- Anthropic — Skills: https://code.claude.com/docs/en/skills
- Serena (symbol-level MCP): https://github.com/oraios/Serena
- code-review-graph (Tree-sitter knowledge graph): https://github.com/tirth8205/code-review-graph
- claude-context (semantic search MCP, Zilliz): https://github.com/zilliztech/claude-context
- RTK — Rust Token Killer: https://github.com/rtk-ai/rtk
- token-economy-kit (read-guard + scout pattern): https://github.com/dani-lore/token-economy-kit
- caveman (output brevity skill): https://github.com/JuliusBrussee/caveman

> Savings percentages quoted by third-party tools are the authors' own benchmarks. Always validate against your own Phase 0 tasks.
