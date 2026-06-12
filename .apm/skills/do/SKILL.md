---
name: do
description: Do a task end-to-end — implement, PR, CI loop, ship. ONLY invoke when the user explicitly types `/do` or `$do`; never auto-select from a natural-language request, even one that sounds like an end-to-end task.
argument-hint: "<issue-url | prompt> [--review] [--no-vcs] [--minimal] [--from <step-id>]"
---

# Do Workflow

Take a task and do it top-to-bottom: research, branch, implement, pass CI, open a PR, and ship. (Under `--no-vcs`,
extend the working tree in place — no branch, commit, or PR.)

> All paths in this skill are relative to the skill's base directory.

**This is a workflow graph.** Step order, skip predicates, and pattern configs live in [`workflow.ncl`](workflow.ncl);
each step's activity is a node file under [`nodes/`](nodes/). The agent is the runtime — there is no separate engine.

**Mostly autonomous.** Do NOT use `AskUserQuestion` at any point (except during the `--review` planning pause). Make
sensible default choices and keep moving.

## How to walk the graph

**Convention: every script invocation is prefixed with `bash` and uses the absolute path
(`.../skills/do/scripts/<name>`).** The scripts under `scripts/` (and `scripts/steps/`) have no
shebang; they are intentionally non-executable. This prevents accidental direct execution —
`scripts/do-driver init` returns `Permission denied` because the file isn't executable, while
`bash scripts/do-driver init` always works. The agent should follow this convention literally:
do not drop the `bash` prefix in commands, and do not rely on the shebang.

**Jujutsu gotcha: `jj new` moves `@` to a new empty change; `jj new --no-edit` does NOT.** If the agent wants
to start a new change (e.g., to add followup work on top of an existing WIP), use bare `jj new`. The
`--no-edit` flag is for the rare case where you want to create a new change but keep editing the current
one — almost never what the workflow wants. Using `--no-edit` by accident means the subsequent edits
land in the existing change, not the new one; the workflow then has no place to put the new work.

1. Parse arguments: `[--review] [--no-vcs] [--minimal] [--from <step-id>] <task>`
2. Call `bash scripts/do-driver init <flags> <task>` to initialize state.
3. Seed the task checklist using Nickel:
   ```bash
   bash scripts/nickel-cli cli_seed "<from>"
   ```
   This returns `[{ name, initial_status }]` — mark `completed` steps and seed the todo UI.
4. For each step, ask Nickel what to do next:
   ```bash
   next=$(bash scripts/nickel-cli cli)
   ```
   This returns `{ step, skip, pattern, instructions, requires, pattern_config }`.
    - If `skip` is true, call `bash scripts/do-driver skip <step> <reason>` and continue.
    - Otherwise: call `bash scripts/do-driver start <step>`, read `nodes/<step>.md`, do the work, then call
      `bash scripts/do-driver end <status> "<verification>" [reason]`.
5. When Nickel returns `{ done = true }`, call `bash scripts/do-driver summary`.

## Arguments

The workflow is **forge-aware**: it auto-detects whether the repo lives on GitHub or elsewhere during the **sync** step.
Only GitHub has an active code path today — Bitbucket/other forges gracefully skip PR-related steps.
Tracking: [srid/agency#10](https://github.com/srid/agency/issues/10).

- `--review`: Pause after **research** for user plan approval via `EnterPlanMode`/`ExitPlanMode`, then continue
  autonomously. **Incompatible with `--from=<non-default>`** (any entry that skips research — `followup`,
  `post-implement`, `polish`, `ci-only`): the plan-approval pause would be silently dropped. `do-driver init`
  errors out on the conflict; drop one of the flags.
- `--no-vcs`: Extend the working tree **in place** — do not create a branch, commit, push, or touch any PR. VCS-mutating
  nodes skip with `reason="--no-vcs"`.
- `--minimal`: Skip **docs**, `hickey-lowy`, **police**, and **evidence** (omitted from todo list entirely).
- `--from <step-id>`: Start from a specific node. Entry points: `default`→sync, `followup`→implement, `post-implement`
  →fmt, `polish`→hickey-lowy, `ci-only`→ci.

## Results Tracking

Every node is bookended by `bash scripts/do-driver start <name>` before work and
`bash scripts/do-driver end <status> "<verification>" [reason]` after verification. The driver wraps `bash scripts/do-results`,
which persists step records in `.do-results.json`.

**Trust the driver's stdout.** Every mutation echoes a one-line confirmation.

The `bash scripts/do-results` script tracks:

- Step `status` — `passed`, `failed`, or `skipped`.
- `active` — state enum (`working`, `waiting`, `false`). The stop hook uses this.
- Workflow `status` — `completed` or `failed`.

**Workflow fields** stashed via `do-driver set <field> <value>`:

- `vcs` — `git`, `jj`, or `unknown`. Populated by `bash scripts/steps/sync` after VCS detection.
- `forge` — `github`, `bitbucket`, or `unknown`. Populated by `bash scripts/steps/sync` after forge detection.
- `noVcs` — `true` or `false`. Reflects the `--no-vcs` flag.
- `minimal` — `true` or `false`. Reflects the `--minimal` flag.
- `review` — `true` or `false`. Reflects the `--review` flag.

**Commands** (invoke with the full path, e.g. `.../skills/do/scripts/do-results ...`):

- `init` — initialize the workflow's lifecycle skeleton. Echoes `init: startedAt=<ts>`.
- `step-start <name>` — call before step work. Echoes `pending: <name>`.
- `step-end <status> "<verification>" ["<reason>"]` — call after verification. Echoes
  `recorded: <name> <status> (steps=<count>, pending=<none|name>)`.
- `step <name> <status> "<verification>" <startedAt> <completedAt> ["<reason>"]` — single-call form used by
  `bash scripts/steps/sync` where `startedAt` was captured in shell. Echoes `recorded: <name> <status> (steps=<count>)`.
  Agent code should prefer `step-start` / `step-end`.
- `set <field> <value>` — set an arbitrary top-level field. Used both for lifecycle (`set active waiting`,
  `set status completed`) and for /do-specific values that sync stashes (`set forge github`, `set noVcs false`). Echoes
  `set: <field>=<value>`.

**Discipline**:

- Bookend every step with `step-start` at the top and `step-end` at the bottom. Calling `step-end` without a prior
  `step-start` is an error; calling `step` with `now` for both timestamps collapses duration to 0 — neither pattern is
  allowed. Exceptions: `sync` is recorded by `bash scripts/steps/sync` itself, and skipped steps (duration always 0) may use
  back-to-back `step-start` / `step-end skipped`.
- Don't run `date` yourself or guess timestamps — `do-results` resolves UTC internally.

## Progress tracking

Drive the harness's native todo UI so the user sees a live checklist. Use `cli_seed` from Nickel to get the initial step
list with correct statuses.

Rules:

- **Flip to `in_progress` when a step starts, `completed` when it verifies.** One step `in_progress` at a time.
- **Retries stay `in_progress`.** If `check`, `test`, or `ci` loop through their retry budget, do **not** bounce the
  task state back to `pending` or flicker it — leave it `in_progress` until the step finally verifies (or the retries
  exhaust and the workflow fails).
- **`--from <step>` entry points**: still seed the full list (minus any `--minimal` omissions). Mark steps earlier than
  the entry point as `completed` immediately after seeding, so the checklist shows a consistent view regardless of entry
  point.
- **Skipped steps that stay in the list** (e.g. `branch`/`commit`/`create-pr` under `--no-vcs`, or PR steps on
  non-GitHub forges) go straight to `completed`. Record the skip with a back-to-back
  `bash scripts/do-results step-start <name>` / `bash scripts/do-results step-end skipped ... "<reason>"`; the task list just
  shows the step as done. `--minimal` skips are **not** in this category — they're omitted from the seeded list
  entirely (see above), so there's no task entry to flip.
- **Failure**: if retries exhaust and the workflow halts, leave the failing step `in_progress`, mark `done` `completed`
  after the failure summary is written, and run `bash scripts/do-results set status failed`.

### sync

Run the `bash scripts/steps/sync` script in this skill's directory, passing `true` or `false` for `--no-vcs`:

```
bash .../skills/do/scripts/steps/sync <noVcs>
```

The script:

- Detects the VCS type (`.jj/` → `jj`, `.git/` → `git`). All subsequent VCS operations delegate to `bash scripts/vcs-op`
  which maps semantic operation names to the active tool.
- Fetches from the remote (git: `git fetch origin`; jj: `jj git fetch`). For git repos, also pins `origin/HEAD`.
- If `--no-vcs` is **not** set and the branch is behind origin (ahead-count 0), fast-forwards with `git pull --ff-only`.
  jj repos skip this step — `jj git fetch` already updates remote bookmarks, and moving to the latest remote state is an
  explicit `jj new <remote-bookmark>` operation.
- Prints the dirty-tree hint to stderr (no pause) when the tree is dirty and `--no-vcs` is not set:

  > _Dirty tree detected. Continuing will create a fresh branch on top of these changes. If you wanted the agent to
  extend your WIP in place without touching VCS, re-run with `--no-vcs`._

- Classifies the forge from the remote URL (git: `bash scripts/vcs-op remote-url`; jj: `jj git remote list`) — `github.com` →
  `github`, `bitbucket.` (covers `bitbucket.org` and self-hosted servers like `bitbucket.juspay.net`) → `bitbucket`,
  otherwise `unknown`.
- Calls `bash scripts/do-results init` then `bash scripts/do-results step sync passed ...`.
- Prints `vcs=<value>`, `forge=<value>`, `branch=<value>`, `defaultBranch=<value>` on stdout for downstream steps.

**Only `github` has an active code path today.** Both `bitbucket` and `unknown` cause forge-dependent steps (PR
creation, PR comments, PR edits, CI status) to skip gracefully. Bitbucket support is planned —
see [srid/agency#10](https://github.com/srid/agency/issues/10).

**Verify**: Script exited 0 and printed `vcs=`, `forge=`, `branch=`, `defaultBranch=` lines on stdout. (Sync silences
`do-results`' own confirmation echoes so the protocol stays clean.)
 
---

### research

Research the task thoroughly before writing code.

- If given a GitHub issue URL **and** the forge is GitHub (the issue body can be fetched — `mcp__vcs__forge_pr_view` is the toolkit-level read path; issue-view is on the same surface), fetch the issue. On non-GitHub forges, treat any issue-like URL as opaque context — use the prompt text as-is and do not attempt to fetch. (Bitbucket issue/Jira fetching is tracked in #10.)
- **Never assume** how something works. Read the code. Check the config.
- If the prompt involves external tools/libraries, prefer `git clone` to a scratch dir (e.g. `/tmp/<name>`) at the
  version the project actually uses, then read the source on disk with `Read`/`Grep`/`Glob`. Fall back to `WebSearch`/
  `WebFetch` only when the source genuinely isn't a clonable repo (vendor docs, blog posts, RFCs).

**Delegation rule — keep the main context lean.** Before your third `Read` in this step, stop and delegate the rest via
`Agent(subagent_type=Explore)`. Main-context reads are reserved for:

(a) specific files the user named in the prompt,
(b) verifying a specific file:line an Explore subagent cited — and only with `offset`/`limit`, never full-file.

Anything that smells like "map the codebase", "find all callers", "understand how X works across the repo" — delegate.
The Explore subagent returns a file:line map; keep that map and reference it in later steps instead of re-reading. Use
`Grep`/`Glob` before `Read`: if the question can be answered by searching, don't open the file.

**Verify**: Can articulate what needs to change, where, and why, with file:line citations drawn from the research map (
not re-read in main context).

**If `--review`**: hand off to **plan-approval** (see `nodes/plan-approval.md`). The EnterPlanMode/ExitPlanMode
instructions live in the plan-approval node, not in this step.

---

### branch

**If `--no-vcs`**: Skip this step entirely with status `skipped` and reason `"--no-vcs"`. Stay on the current branch —
do not create, commit, or push anything. Move to **implement**.

Read `vcs` and `defaultBranch` from `.do-results.json`. Then:

```
bash .../skills/do/scripts/vcs-op branch <descriptive-name> <defaultBranch>
```

The script handles the VCS-specific details: git creates `git branch <name> origin/<default>`; jj creates
`jj new <default>` followed by `jj bookmark create <name> -r @`.

That's it — just the local branch. No commit, no push, no PR. The branch is pushed later in **commit**, and the PR is
created in **create-pr** after all changes are done.

**Verify**: `bash scripts/vcs-op head-revision` returns the new branch name (not master/main).
 
---

### implement

The test-first rule depends on what the change is:

- **Bug fix**: write a failing test first (e2e or unit, whichever is appropriate), then fix the bug.
- **New behavior** — anything that fails at runtime if it's wrong: new endpoints or routes, new services or modules,
  configuration paths, environment variables, secrets wiring, network connectivity, data persistence (migrations,
  preStart scripts, schema changes), auth/OIDC flows. Write an integration or unit test covering the new behavior *
  *before** implementing. NixOS service modules need a VM test; new HTTP endpoints need an e2e or integration test; new
  modules with logic need at least a unit test.
- **Otherwise** — documentation, refactors with no behavioral change, purely internal cleanups, dependency bumps that
  don't change behavior. Just implement the planned changes; no test-first requirement.

If you're not sure which bucket the change falls into, treat it as new behavior. The cost of an unnecessary test is
small; the cost of a silent deployment failure is not.

Prefer simplicity. Do the boring obvious thing.

**E2E coverage**: When the change introduces multiple user-facing paths (e.g., a dialog that appears under different
conditions), write e2e scenarios for **each distinct path**. Enumerate the user-visible paths, then check that every one
has a corresponding test.

**Verify**: Code changes match the planned approach. For bug fixes and new-behavior changes, at least one test exercises
the changed behavior; multi-path changes have one test per distinct user-visible path. Refactor/docs/cleanup diffs are
exempt.
 
---

### check

Read `.agency/do.md` and look for a `## Check command` section — a fast static-correctness gate (e.g. `tsc --noEmit`,
`cargo check`, `cabal build`, `mypy`, `dune build @check`). Run it.

This is the cheapest gate in the pipeline, so it runs first — fail fast on broken code before any downstream step does
work over it. If no check command is documented, skip this step with a note.

**Verify**: Check ran without errors, or no command configured.
**If failed** (max 3 attempts): Fix the errors and re-run check. Do not fall back to **implement** — the agent is
already in fix mode and the failure is local to just-written code.
 
---

### docs

**If `--minimal`**: Skip with status `skipped` and reason `"--minimal"`. Move to **fmt**.

Read `.agency/do.md` and look for a `## Documentation` section listing which docs to keep in sync (e.g., README.md).
Compare those files against changes in this PR.

If no documentation files are documented, skip this step with a note.

**Verify**: Docs match current code.
**If outdated** (max 3 attempts): Fix the outdated sections and re-verify.
 
---

### fmt

Read `.agency/do.md` and look for a `## Format command` section. Run it.

If no format command is documented, skip this step with a note.

**Verify**: Format command ran without error, or no command configured.
 
---

### commit

**If `--no-vcs`**: Skip with status `skipped` and reason `"--no-vcs"`. Move to **hickey+lowy**. The working-tree changes
stay uncommitted — that is the point.

Create a NEW commit (never amend) with a conventional commit message for the primary implementation. Use the
VCS-agnostic dispatcher:

```
bash .../skills/do/scripts/vcs-op commit "<message>"
bash .../skills/do/scripts/vcs-op push <branch>
```

Git: stages all changes with `git add -A`, commits with `git commit -m "..."`, pushes with
`bash scripts/vcs-op push <branch>`.
Jujutsu: auto-snapshots the working copy, describes with `jj describe -m "..."`, then `jj new` to start a fresh
change. Before the `jj new`, the bookmark is on `@` (the change being committed); after, `@` is the new empty change
and the bookmark is now on `@-` (the just-described commit). If the working copy was started with `jj new` before
calling `vcs-op commit` (the followup case — see **How to walk the graph**), the bookmark is somewhere up the
parent chain (`@--`, `@---`, ...). `vcs-op commit` walks the chain to find the bookmark and moves it to `@-` so the
subsequent `bash scripts/vcs-op push <bookmark>` lands on the new commit. (Note: do **not** start the new change
with `jj new --no-edit` — see the Jujutsu gotcha above.) Pushes the bookmark with
`jj git push --bookmark <name>`. `bash scripts/vcs-op log-head` returns the just-described change (`@-` for jj,
equivalent to `git log -1 --oneline` showing HEAD), so the verify below works for both VCSes.

This is the **primary feature commit**. Downstream **hickey+lowy** and **police** steps produce their own follow-up
commits — one per finding or violation addressed — which keeps the PR history a readable progression of "what was built,
then what was refined" rather than a single opaque squash.

**Verify**: `bash scripts/vcs-op log-head` shows a new commit/change on the feature branch, and it's pushed to remote.
 
---

### hickey + lowy

**If `--minimal`**: Skip with status `skipped` and reason `"--minimal"`. Move to **police** (which will also skip under
`--minimal`). Do not spawn either sub-agent.

Invoke `hickey` and `lowy` as two **parallel sub-agents** via the harness's agent tool (`subagent_type: "hickey"` and
`subagent_type: "lowy"`). On Claude Code this is the `Agent` tool. On opencode this is the `task` tool (with
`subagent_type` parameter). On Codex this is the sub-agent spawning tool for delegated work. Invoking `/do` is explicit
authorization to run these two review agents; do not wait for a second user prompt before spawning them.

**Fallback, never skip.** If the harness cannot honor the model declared in the reviewer skill's frontmatter, run hickey
and lowy as sub-agents on the available model instead — this is the expected path on harnesses that ignore Claude Code's
`model:` skill extension (opencode, Codex, etc.). If a sub-agent invocation fails for harness/tooling reasons before
producing a review, retry that reviewer once; if it still cannot produce a sub-agent review, run that review in the main
model by loading the reviewer skill against the same diff. This fallback is slower and uses more main-context budget,
but it is still the `/do` hickey+lowy step. Do not replace it with an informal/manual review, and do not mark the step
`skipped` because a preferred model was unavailable.

**Why post-implement, not pre-implement.** Hickey's complecting critique and Lowy's volatility lens both bite harder on
a concrete diff than on a plan sketch. Reviewing a plan tends to surface generic concerns; reviewing a real diff
surfaces the specific interleavings and boundary misalignments that matter. Running here also means the review covers
*everything* the diff contains — including whatever the plan glossed over and whatever drifted during implementation.

<use_parallel_tool_calls>
For maximum efficiency, invoke the `hickey` and `lowy` Agent tools **in parallel** rather than sequentially. You MUST
use parallel tool calls: emit both `Agent` tool_use blocks (one with `subagent_type: "hickey"`, one with
`subagent_type: "lowy"`) in a single response, with no other tool calls or text in that response.
</use_parallel_tool_calls>

Each `Agent` prompt must be self-contained (sub-agents do not inherit this conversation's context). Brief each one with:

- The full task prompt plus anything relevant that **research** uncovered (file paths, intended approach, key
  constraints)
- The scope to analyze: the actual diff, obtained via `bash .../skills/do/scripts/vcs-op diff-range <defaultBranch>` —
  this is the same scope regardless of entry point (default or followup), since the branch at this point holds the
  primary feature commit (plus any cumulative followup commits) and no further work is pending
- **Duplication-audit hint**, when the diff adds new files — check with
  `.../skills/do/scripts/vcs-op new-files <defaultBranch>` and only include the hint if the output is non-empty. The
  hint tells the reviewer to start with the codebase survey their skill describes (`hickey` Layer 3, `lowy` §1 "Check
  for prior encapsulation"): find the canonical in-repo pattern for the same *kind* of operation (picker, dialog,
  popover, list view, list-edit primitive, scheduler, error type, config loader, fetcher, …) and flag it as the headline
  finding if the diff reinvents rather than extends it. Skip the hint entirely when the diff has no new files — pure
  refactors and bug fixes inside existing abstractions don't benefit from the survey and the audit budget isn't worth it
  there.

The sub-agent already knows to read its skill file and follow that methodology; don't re-state it in the prompt.

**Do not seed structural questions.** The implementer's prompt must NOT include pre-formed questions like _"Is module X
the right home for function Y?"_, _"Does the new field complect concerns A and B?"_, or _"Should constructor C be a
sum?"_ — that framing shopping-lists the answer and produces circular reasoning at the reviewer (e.g. "primary consumer
of `logPathFor` is `CommitStatus`" — true only because the implementer placed it there). Hickey and Lowy each have their
own methodologies for generating findings; the reviewer reads the diff cold and surfaces what its lens shows. Anything
beyond "here's the diff and the change rationale" is implementer bias bleeding into the review. If a specific concern
feels worth flagging to the reviewer, that's evidence the implementer already smelled the problem — fix it in the diff
before sending it to review, not by routing the question through a sub-agent for permission.

The **duplication-audit hint** above is the one allowed exception: it's a meta-process reminder (run the survey your
skill describes), not a seeded finding about *this* diff. It points the reviewer at the codebase, not at a specific
concern within the diff — that's the line. If the diff doesn't add new files, drop the hint and let the lens run
unprimed.

**Model selection lives in the skill, not here.** Both `hickey/SKILL.md` and `lowy/SKILL.md` declare `model: sonnet` in
their frontmatter — Claude Code honors this and runs the review on Sonnet to keep the per-task cost cheap;
opencode/Codex ignore the field (it isn't part of the Agent Skills standard) and fall through to the active model, which
is the right behavior for harnesses that don't have Sonnet. Don't pass `model:` at the `Agent` tool level — the skill
frontmatter is the single source of truth.

**No deferrals.** The hickey and lowy skills emit two dispositions: **Fix in this PR** and **No-op**. There is no Defer.
`/do` is not optimizing for minimal diff — it is optimizing for the simpler artifact landing in `master`. A PR that
grows from 50 lines to 400 because hickey caught a real fragmentation bug is a *better* PR, not a worse one; the
alternative is shipping the complected version and trusting a "broader refactor" follow-up that statistically never
happens.

If a sub-agent emits anything resembling a defer — `Defer #N`, "out of scope", "follow-up", "pre-existing, separate
PR", "should be its own change", any phrasing that punts a finding to a future issue — treat it as a sub-agent rule
violation. Flip the disposition to **Fix in this PR** unconditionally and apply the fix here. Do not create a follow-up
issue, do not record the finding as deferred in the PR body, do not surface it as outstanding structural debt. The only
way out of a finding is through it.

(`No-op` survives without code action — but it is narrow: the diff already deletes the offending code, or the finding is
subsumed verbatim by another entry in the same review. Anything resembling deferred-work-for-later is a Fix, not a
No-op.)

Findings that genuinely require coordination outside this repo (upstream library bug, breaking dep upgrade, schema
migration that must ship separately) shouldn't have surfaced as findings of this structural review in the first place;
if one did, apply a local workaround or interface boundary in this PR rather than punt — and flag the upstream
dependency in the PR description as a strategic note, not as a deferred finding.

**Cross-validate the parallel findings.** Hickey and Lowy ran in parallel without seeing each other's output. Each
reviewer's local-optimum call can produce a problem the other lens should have caught — a Lowy "consolidate `helper`
into module X" can land in a destination that Hickey would have flagged as two volatility axes braided into one module,
and a Hickey "decompose interleaved roles" split can land both halves into modules whose imports Lowy would have called
fragmentation. Neither lens, running alone, sees the cross-effect.

Skip this phase if **both** reviewers returned zero findings — there is nothing for the other lens to second-guess.
Otherwise, for each reviewer that produced findings, spawn a second invocation of *that same skill* (
`subagent_type: "hickey"` or `subagent_type: "lowy"`) with a self-contained prompt containing:

- The actual diff (`bash .../skills/do/scripts/vcs-op diff-range <defaultBranch>`).
- The other reviewer's full findings output (paste it verbatim — the cross-validator must see the recommendations being
  audited, not a summary).
- The question, phrased neutrally: _"Apply your lens to the diff **and** to the other reviewer's recommendations. Does
  any recommendation, if applied, create a problem your lens would flag? If yes, surface it as a new finding with the
  same Actions disposition rules (Fix in this PR / No-op, no Defer)."_

Run the two cross-validation calls in parallel (single message, both `Agent` blocks). Each call is cheap because the
diff and the other-side findings fit in one prompt. If either cross-validator surfaces a new finding, treat it
identically to a first-pass finding — apply as its own commit per the rules below, with commit prefix
`refactor(hickey)`/`refactor(lowy)` and a short label indicating it came from cross-validation (e.g.
`refactor(hickey): cross-validate — placement audit on logPathFor`).

After the audit (and cross-validation, when run), every finding lands as a commit, except entries dispositioned **No-op
**.

**Apply each "Fix in this PR" finding as its own commit** — do not batch multiple findings into one commit. A reviewer
reading the PR's commit history should be able to read one "address hickey finding: decomplect viewportDimensions"
commit at a time and follow the structural refinement as a sequence, not decode a grab-bag diff. For each finding in
turn:

1. Apply the fix narrowly — only the lines that address this specific finding.
2. Run the project's format command (from **fmt** instructions) on the changed files, if one is configured.
3. `.../skills/do/scripts/vcs-op fix-commit "refactor(hickey): <short finding label>"` (or `refactor(lowy): …` depending
   on the lens). The body of the message should restate the finding in one line so the commit is self-explanatory in the
   log.

**Under `--no-vcs`**: Skip the commit/push steps entirely. Apply fixes to the working tree and move on — the user will
review the combined working-tree delta themselves. Record the step as passed with verification noting "--no-vcs: fixes
applied to working tree, not committed."

**Verify**: Both hickey and lowy produced review output using their respective skills, either through sub-agents or the
main-model fallback. Cross-validation ran (or was correctly skipped because both reviewers returned zero findings).
Every finding — first-pass or cross-validation — has an action recorded, either **Fix in this PR** or **No-op** (no
defers; if the sub-agent emitted one, the audit step above flipped it to Fix in this PR). Every "Fix in this PR" finding
has a corresponding commit on the feature branch (check via `bash scripts/vcs-op log-range <defaultBranch>`), except under
`--no-vcs`. No unactioned findings; no deferred findings.
 
---

### police

**If `--minimal`**: Skip with status `skipped` and reason `"--minimal"`. Move to **test**. Do not invoke `/code-police`.

Use `bash .../skills/do/scripts/vcs-op diff-names <defaultBranch>` to check if the PR contains code changes. If all
changed files are documentation-only (e.g., `.md`, `.txt`, `README`, docs/) — skip this step with a note.

Otherwise, invoke the `/code-police` skill via the Skill tool. It runs three passes: rule checklist, fact-check, and
elegance (which delegates to `/simplify` when available).

When `/code-police` asks about scope: **changes in the current branch/PR only**.

**Commit each violation fix individually.** The same rule as **hickey + lowy**: PR history is the story of the work, and
a reviewer should see one commit per rule violation or elegance refinement, not a lump "police pass" commit covering
eight unrelated things.

For each violation reported by `/code-police` (across all three passes), in turn:

1. Apply the fix for that one violation — scope the edit tightly.
2. Run the project's format command on changed files, if configured.
3. `bash .../skills/do/scripts/vcs-op fix-commit "<prefix>: <short description>"` with the conventional prefix
   identifying the pass and rule:
    - Rules pass: `fix(police): <rule-id> — <short description>` (e.g.
      `fix(police): no-dead-code — remove commented-out fallback`)
    - Fact-check pass: `fix(police): fact-check — <short description>` (e.g.
      `fix(police): fact-check — propagate error from loader`)
    - Elegance pass (`/simplify`-applied or inline-loop-applied): `refactor(police): elegance — <short description>`

For the elegance pass specifically: `/simplify` applies fixes in batches across three lenses (reuse, quality,
efficiency). Commit each distinct refactor as a separate commit — do not roll them into one "elegance" commit. If a lens
produces multiple independent changes (two reuse-via-helper refactors in different files, say), those are separate
commits too.

**Under `--no-vcs`**: Skip the commit/push steps. Apply fixes to the working tree and continue. The user reviews the
combined delta.

**Verify**: All 3 passes clean ("All clear"). Under `--no-vcs`, the tree reflects the fixes; otherwise
`bash scripts/vcs-op log-range <defaultBranch>` shows one commit per violation addressed.
**If violations found** (max 3 attempts): Fix the violations (one commit per fix, as above) and re-invoke
`/code-police`.
 
---

### test

Read `.agency/do.md` and look for a `## Test command` section. Run only the tests relevant to the code paths changed in
this PR.

Use `bash .../skills/do/scripts/vcs-op diff-names <defaultBranch>` to identify changed files and determine which tests
are relevant.

If changes are purely internal with no user-facing impact, unit tests may suffice — skip e2e if no relevant scenarios
exist. If no test command is documented, skip with a note.

**Coverage gap check**: After the test command exits 0, confirm at least one of the tests run actually exercised the new
behavior (per the **implement** step's classification). A green run that didn't touch the changed code paths — e.g. a
new NixOS service module with no corresponding VM test, or a new endpoint with no integration test — is a coverage gap,
not a pass. Refactor/docs/internal-cleanup diffs are exempt. The implement step should have caught this; if it didn't,
treat it as a real failure: write the missing test, then loop through **fmt** → **commit** → **test** as below.

**Verify**: Tests pass (exit code 0) **and** the new behavior is covered, or the diff is exempt from the coverage check,
or no relevant tests to run.
**If failed** (max 4 attempts): Analyze the failure. If flaky, re-run. If real: fix → go to **fmt**, then retry.
 
---

### create-pr

**If `--no-vcs`**: Skip with status `skipped` and reason `"--no-vcs"`. There is no PR to create. Proceed to **ci**.

**If `!state.forgeCapabilities.prCreate` (forge can't open a PR — e.g. unknown, Gitea with no upstream PR-create)**:
Skip with status `skipped` and reason:

- `"unsupported forge (no vcs-mcp toolkit recognition)"` when `state.forge = 'unknown` (the toolkit
  couldn't classify the remote host; "non-unknown forge: unknown" reads as gibberish, so use a distinct reason).
- `"non-<forge.kind> forge: <forge.kind>"` otherwise (the standard string interpolation; e.g.
  `non-bitbucket forge: bitbucket`).

Proceed to **ci**. (Bitbucket `bkt pr edit` wiring is tracked in #10.)

**If `state.forgeCapabilities.prCreate` (forge can open a PR — typically GitHub today)**:

Check whether a PR already exists for this branch (`gh pr view`).

**If no PR exists** (first run, normal path):

1. Create a draft PR: `gh pr create --draft`

   **MANDATORY**: Load the `forge-pr` skill (via Skill tool) BEFORE writing the PR title/body.

2. **Post hickey/lowy results**: Post the hickey and lowy analysis as a PR comment using `gh pr comment` with a
   `## [Hickey/Lowy](https://kolu.dev/blog/hickey-lowy/) Analysis` header (the heading links to the blog post explaining
   the two lenses, mirroring how the final step status comment links `/do` to the agency repo). Always post when the
   steps ran — reviewers should see the structural analysis even if every finding was a No-op.

   **Format the comment with a leading findings ledger.** Compose a single table from both sub-agents' Actions
   sections — one row per finding — so a reviewer can see disposition at a glance without parsing paragraphs. Put each
   lens's prose underneath as rationale:

   ```md
   ## [Hickey/Lowy](https://kolu.dev/blog/hickey-lowy/) Analysis

   | # | Lens   | Finding                                  | Disposition         |
   |---|--------|------------------------------------------|---------------------|
   | 1 | Hickey | viewportDimensions complects two roles   | Fixed in this PR    |
   | 2 | Lowy   | useViewport encapsulates ghost concern   | Fixed in this PR    |
   | 3 | Lowy   | clipboard.ts named after a consumer      | ⚠️ **No-op**        |

   ### Hickey rationale
   <prose from the hickey sub-agent>

   ### Lowy rationale
   <prose from the lowy sub-agent>
   ```

   The Disposition cell mirrors the sub-agent's Actions disposition verbatim — **Fixed in this PR** or **No-op** (
   deletion-only / subsumed by another finding). **Render every No-op as `⚠️ **No-op**`** (warning emoji + bold) so the
   reviewer's eye lands on it; No-op rows are the ones a human most needs to scrutinize (a finding the reviewer
   acknowledged but didn't fix), and plain text lets them blend into the Fixed-in-this-PR rows above. There is no
   Deferred disposition; if a sub-agent emitted one, the audit step above flipped it to Fixed in this PR. The Finding
   cell is the short bolded label the sub-agent emits at the start of each Actions entry. If both lenses produced zero
   findings, write a one-line "No findings — analysis below" instead of an empty table.

**If PR already exists** (followup runs, `--from` entry points):

Re-check the PR title/body against current scope. If scope changed, update via `gh pr edit` per the `forge-pr` skill.

**Why this runs before `ci`**: The draft PR is the canonical home for CI status. Opening it before CI runs means CI
checks land directly on the PR, reviewers see the run history as it happens, and a failing run doesn't leave an orphaned
branch with red statuses and no PR to explain them. If retries exhaust in **ci**, the draft PR remains as the artifact
of the failed attempt — visible, reviewable, and ready to resume via `--from ci-only`.

**Verify**: Draft PR exists (`gh pr view` succeeds), PR title/body matches the delivered scope, hickey/lowy findings
posted if any.
 
---

### ci

Read `.agency/do.md` and look for a `## CI command` section, plus any verification method documented there. Run CI with
`run_in_background: true` if the command takes more than a few seconds.

**Never pipe CI to `tail`/`head`**, and **never append `2>&1`** — background mode captures both streams.

**Active state**: Before waiting for background CI, run `bash scripts/do-results set active waiting`. When CI returns (
success or failure), run `bash scripts/do-results set active working` before proceeding. This lets the stop hook allow
graceful exits while the agent is idle.

CI commands are typically local (e.g. `nix flake check`, `just ci`, `make ci`) and are forge-independent — **run them
regardless of forge**. Only the *verification method* may be forge-specific: if `.agency/do.md` describes verification
via `gh` commit-status checks and `!state.forgeCapabilities.prChecks`, fall back to exit code + command output for verification
on forges without a checks command, and note this in the step record. (Bitbucket `bkt pr checks` wiring is tracked in #10.)

**Verify**: Use the verification method described in `.agency/do.md` (e.g., checking commit statuses on GitHub, reading
CI output elsewhere). If no CI command is documented, skip with a note. **The CI result must cover `HEAD`.** Before
recording the step as passed, compare the commit SHA that CI ran against with
`.../skills/do/scripts/vcs-op head-commit-sha`. If they differ (e.g., a commit was pushed after CI started — whether
from a fix retry, user-requested changes, or any other source), re-run CI against the current HEAD. CI passing on a
stale commit does not satisfy verification.

**On failure** — read logs or output to diagnose.

**Flaky vs real**: A test is flaky only if it **passes on a subsequent retry**. Consistent failure = real bug. Before
retrying, read the failing test code to judge if the failure pattern is inherently flaky (race conditions, timing, async
waits).

**If flaky** (max 3 retries): Retry just the failing step.
**If real bug** (max 5 fixes): Fix → **fmt** → **commit** → retry CI. Under `--no-vcs`, drop **commit** from the loop (
Fix → **fmt** → retry CI). The draft PR already exists — subsequent pushes update it automatically, no re-run of *
*create-pr** needed.
**If retries exhausted**: Set workflow status to `"failed"`, skip to **done**. The draft PR stays open as the record of
the failed attempt.
 
---

### evidence

**Opt-in step.** Most projects skip this. The step exists so projects with empirical "did the feature actually work"
needs — UI screenshots, performance benchmarks, demo recordings, output transcripts — can attach that evidence to the PR
without baking the mechanism into agency.

**If `--minimal`**: Skip with status `skipped` and reason `"--minimal"`. Move to **done**.

**If `--no-vcs`**: Skip with status `skipped` and reason `"--no-vcs"`. There is no PR to attach evidence to.

**If `!state.forgeCapabilities.prComment` (forge can't post PR comments)**: Skip with status `skipped` and
reason `"unsupported forge (no vcs-mcp toolkit recognition)"` when `state.forge = 'unknown`, otherwise
`"non-<forge.kind> forge: <forge.kind>"`. (Bitbucket comment wiring is tracked in #10.)

**Otherwise**: Read `.agency/do.md` and look for a `## PR evidence` section. If `.agency/do.md` is missing, or the
section is missing or empty, skip with status `skipped` and reason `"no PR evidence section in .agency/do.md"` — the
default for projects that haven't opted in.

**If the section is present**:

The section is project-specific and free-form: it can be inline prose describing the capture procedure, a pointer to
another file (`See ./scripts/capture-evidence.md`), a script reference (
`Run ./scripts/capture-pr-evidence.sh and use its stdout`), or any combination. Don't second-guess the form — read it,
then **spawn a sub-agent** (`Agent(subagent_type: "general-purpose", ...)`) so the capture work (MCP calls, screenshot
uploads, gh API requests) doesn't pollute `/do`'s main context.

The sub-agent prompt should include:

- The literal section content from `.agency/do.md`.
- Standard PR context: PR URL, branch name, base branch, current commit SHA, and
  `.../skills/do/scripts/vcs-op diff-names <defaultBranch>` so the sub-agent knows which routes/files to exercise.
- An explicit instruction that the sub-agent's job is to return a single block of markdown (image links embedded, table
  data inline, etc.) suitable for posting under a `## Evidence` heading. The sub-agent should not post the comment
  itself — only return the markdown.

After the sub-agent returns, post its output as one PR comment using `gh pr comment` under a `## Evidence` heading. Use
the **single-quoted heredoc** pattern (see `forge-pr` → "Passing the body to `gh` safely") so backticks and `$` survive
unescaped:

 ```sh
 gh pr comment --body "$(cat <<'EOF'
 ## Evidence
 
 <markdown returned by the sub-agent>
 EOF
 )"
 ```

Embed image/asset URLs inline in the markdown — `gh pr comment` itself cannot attach files; the workflow section is
responsible for telling the sub-agent how to host any binary artifacts so they end up referenceable.

**Verify**: Either the step was skipped per the rules above, or a `## Evidence` PR comment exists (
`gh pr view --comments` or equivalent) populated from the sub-agent's output.
 
---

### done

Present a summary of all steps with their verification status. If any step has a non-success status, retry it (max 3
attempts from done). If still failing after retries, set `status: "failed"`.

`"completed"` requires **all steps `passed`**, with four exceptions that count toward completion:

1. A step `skipped` with `reason` beginning `"non-<forge> forge:"` (detected forge isn't GitHub).
2. A step `skipped` with `reason` `"--no-vcs"` (user opted out of git operations).
3. A step `skipped` with `reason` `"no PR evidence section in .agency/do.md"` (project hasn't opted into the evidence
   step — this is the default).
4. A step `skipped` with `reason` `"--minimal"` (user opted out of structural review / docs / quality gate / evidence on
   a trivial diff).

A `failed` step always blocks `"completed"`. No redefining "passed," no footnote caveats. Update via
`bash scripts/do-results set status completed` or `bash scripts/do-results set status failed` accordingly.

#### Timing summary

Run `bash scripts/steps/done` in this skill's directory. It emits:

1. A markdown timing table (step, status, duration, verification), with any step that took ≥30% of total time shown in *
   *bold**.
2. A total wall-clock line (`startedAt` of first step → `completedAt` of last step).
3. A `**Slowest step**:` line.
4. A `<<<FACTS ... FACTS` block with machine-readable summary data (`totalSeconds`, `slowestStep`, `slowestSeconds`,
   `dominantSteps`, `skippedSteps`, `failedSteps`) — use this to compose optimization suggestions below.

Do not compute durations yourself — the script handles all timestamp arithmetic.

#### Optimization suggestions

Read the `FACTS` block the `done` script emitted and generate 2–4 concrete suggestions for reducing time-to-completion
in future runs. Base these on the actual timing data — for example:

- If **ci** dominates: suggest `--from ci-only` for re-runs, or note which CI sub-step was slowest
- If **research** was slow: suggest pre-reading relevant code before invoking `/do`
- If **test** had retries: note the flaky test and suggest hardening it
- If **police** required fix iterations: note which pass caught issues (rules/fact-check/elegance)
- If **implement** was the bottleneck: suggest breaking the task into smaller PRs

Be specific to this run's data, not generic advice.

#### PR comment & wrap-up

**If `--no-vcs`**: There is no branch or PR to report against. Print the timing table and optimization suggestions to
the terminal only. List the files modified in the working tree via `.../skills/do/scripts/vcs-op dirty` and the
VCS-appropriate status output so the user can see what the agent touched. Remind the user that changes are uncommitted —
the commit/push/PR steps are theirs to run.

**If `!(state.forgeCapabilities.prCreate && state.forgeCapabilities.prComment)` (forge can't open a PR or post a comment)**:
Report the branch name (and remote URL, if available via
`.../skills/do/scripts/vcs-op remote-url`) instead of a PR URL. Print the timing table and optimization suggestions to
the terminal only — do **not** attempt to post a PR comment. (Bitbucket `bkt pr comment` wiring is tracked in #10.)

**If `state.forgeCapabilities.prCreate && state.forgeCapabilities.prComment` (forge supports PR + comment, e.g. GitHub)**:
Report the PR URL. Then post the final step status table as a **PR comment** using
`mcp__vcs__forge_pr_comment`. Use the markdown table and slowest-step line emitted by `bash scripts/steps/done` verbatim (strip the
trailing `<<<FACTS ... FACTS` block — that's internal). Format:

 ```
 gh pr comment --body "$(cat <<'COMMENT'
 ## [`/do`](https://github.com/srid/agency) results
 
 | Step | Status | Duration | Verification |
 |------|--------|----------|-------------|
 | sync | ✓ | 3s | ... |
 | research | ✓ | 45s | ... |
 ...
 | **Total** | | **4m 32s** | |
 
 ### Optimization suggestions
 
 - <2–4 concrete suggestions based on timing data>
 
 Workflow completed at <timestamp>.
 COMMENT
 )"
 ```

 
---

## Entry Points

| ID               | Starts at             | Use case                                |
 | ---------------- | --------------------- | --------------------------------------- |
| `default`        | **sync**              | Full workflow from scratch              |
| `followup`       | **implement**         | Additional changes on existing PR       |
| `post-implement` | **fmt**               | Skip research/impl, start at formatting |
| `polish`         | **hickey+lowy**       | Structural review + quality gate        |
| `ci-only`        | **ci**                | Just run CI                             |

## Rules

- **Never skip steps** (unless Nickel reports `skip = true`, or — for **evidence** — the project hasn't filled in a
  `## PR evidence` section in `.agency/do.md`). Run them in order from entry point to **done**.
- **Every commit is NEW.** Never amend, rebase, or force-push.
- **Feature branches only.** Never commit to master/main.
- **Background for CI.** Run CI with `run_in_background: true`.
- **No questions.** Don't use `AskUserQuestion` outside the `--review` plan pause (post-research).
- **Never stop between steps.** After completing a step, immediately proceed to the next one.
- **Complete the full workflow.** The task is not done until a PR URL (GitHub), a pushed branch name (non-GitHub
  forges), or a working-tree summary (`--no-vcs`) is reported.
- **Exhausted retries = halt.** If `ci` or `test` retries are exhausted, set status to `"failed"` and skip to **done**.
