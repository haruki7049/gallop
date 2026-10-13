# Agent Guidelines for `coffee-chan`

This document defines core principles, architectural invariants, and non-negotiable safety rules for AI agents working on the `coffee-chan` repository.

______________________________________________________________________

## 1. Project Overview & Architecture

`coffee-chan` is a cafe music generation project built with the [`lightmix`](https://github.com/haruki7049/lightmix) audio synthesis library in Zig.

- **Deterministic Generation**: Music generation is treated as a deterministic build artifact. Running `zig build` produces `coffee-chan.wav` directly during the build.
- **Development Environment**: Managed with Nix, `direnv`, and `nix-direnv` for automated environment isolation. Formatting across all languages is handled via `treefmt`.
- **Target Language Version**: Zig `0.16.0`. Avoid unnecessary external dependencies to maintain seamless cross-compilation.
- **Modular Directory Structure**:
  - `src/root.zig`: Main music composition and build-time generation entry point.
  - `modules/`: Reusable audio modules (`filters`, `synthesizers`, `music`, `sequencer`, `phrases`, `banks`); see the Module Layering section of `CONTRIBUTING.md`.
  - `sandbox/`: Prototyping directory for testing synthesizers and scales independently.
  - `build.zig` & `build.zig.zon`: Build definition and package metadata.

______________________________________________________________________

## 2. Strict Safety & Operational Rules (Always Enforced)

- **NEVER MERGE PULL REQUESTS**: AI agents **MUST NEVER** merge PRs (including enabling auto-merge with `gh pr merge --auto`), execute `git merge` into `main`, or directly push commits to the `main` branch autonomously.
- **NEVER PROPOSE COMMITS OR PUSHES UNPROMPTED**: AI agents **MUST NEVER** prompt the user to commit or push, nor propose commit messages unprompted. When instructed by the user or when creating/updating pull requests on topic branches, agents may execute `git commit` and `git push` directly without seeking confirmation.
- **Mandatory Human Approval**: AI agents may create branches, create commits, push topic branches, propose PRs, format code, and run test suites, but the final action of merging changes into `main` rests strictly with the human maintainer.
- **Verification Before Submitting**: All changes must pass `treefmt --fail-on-change`, `zig build`, and `zig build test`.
- **Conventional Commits**: Use conventional commit prefixes (`feat:`, `fix:`, `refactor:`, `docs:`, `build:`, `test:`).
- **Evidence First**: Base all answers and actions on actual file contents and command output. Never speculate or assume.
- **Non-Destructive**: Never perform irreversible actions (file deletions, hard resets, rewriting pushed history such as amending or rebasing pushed commits and force-pushing, pushing to `main`) without explicit user approval. Ordinary pushes of new commits to a topic branch don't need approval (see above).
- **Targeted Edits**: Make minimal, logical changes strictly necessary for the request. Do not modify unrelated files.
- **English-Only Documentation**: All repository documentation, agent skills, code comments, commit messages, and PR descriptions must be written strictly in English. Never include Japanese or any non-English language in repository documentation or skill files.
- **Naming Conventions**: Follow repository naming standards defined in [`docs/NAMING.md`](docs/NAMING.md). In particular, comptime type parameters must always be a single uppercase character (e.g., `comptime T: type`), and functions/methods must use concise verb-only names when context is evident (e.g., `Track.add` rather than `Track.addWave`).
- **GitHub Projects Operations**: When updating GitHub Projects via `gh project item-edit`, always inspect schemas (`gh project field-list`) first rather than assuming field names or values. Update only one field per invocation, as passing multiple `--field` flags silently overwrites previous flags. See [`github-projects`](.agents/skills/github-projects/SKILL.md).
- **Explicit Milestone Assignment Only**: AI agents **MUST NEVER** automatically attach or set GitHub Milestones on Pull Requests or Issues unless explicitly requested or instructed by the user.
- **No Session Links**: Do not include AI session URLs or other internal session identifiers (e.g. a `Claude-Session:` trailer) in commit messages, PR descriptions, issues, or comments. Such links are not accessible from outside the private session, so publishing them in this public repository serves no purpose and only confuses readers. A `Co-Authored-By:` trailer is fine. Exception: if the user explicitly states the session is public and instructs the agent to include its URL, doing so is allowed.

______________________________________________________________________

## 3. Status Assessment Workflow

When asked to check status, assess the situation, or understand workspace context:

1. **Local Git State**: Inspect working tree (`git status -s -b`) and recent commits (`git log -n 5 --oneline`).
1. **GitHub PRs**: Check PR status (`gh pr status`) and current PR details (`gh pr view`).
1. **GitHub Issues**: Check relevant open issues (`gh issue list --limit 5`).
1. **Environment Health**: Verify build and test status (`treefmt --fail-on-change`, `zig build`, `zig build test`).
1. **Synthesis**: Report a concise, structured status covering local state, remote GitHub state, and environment health.

______________________________________________________________________

## 4. Workspace Skills

Detailed runbooks and procedural workflows are maintained as workspace skills under `.agents/skills/` (and accessible via `.opencode/skills/`):

| Trigger / Context | Skill to Read | Purpose |
| :--- | :--- | :--- |
| Deep investigation, complex code search | [`investigate`](.agents/skills/investigate/SKILL.md) | Non-destructive investigation guidelines |
| Commit conventions & policies | [`git-commit`](.agents/skills/git-commit/SKILL.md) | Commit conventions and prohibition of unprompted commit/push proposals |
| Deleting files, overwriting, git push/reset | [`irreversible`](.agents/skills/irreversible/SKILL.md) | Pre-checks and confirmation prompts |
| Testing, verifying builds or behavior | [`verify`](.agents/skills/verify/SKILL.md) | Minimal, high-signal verification steps |
| Bumping `lightmix` or `zon2nix` | [`update-dependencies`](.agents/skills/update-dependencies/SKILL.md) | Procedures for dependency updates and `.deps.nix` |
| Updating GitHub Projects fields, issues/PRs | [`github-projects`](.agents/skills/github-projects/SKILL.md) | Procedures, caveats (single-field updates), and schema validation for Projects v2 |
| Preparing PRs, formatting, pre-submission checks | [`pr-workflow`](.agents/skills/pr-workflow/SKILL.md) | Verification command table, commit rules, and PR requirements |
