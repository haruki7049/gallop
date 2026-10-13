---
name: git-commit
description: Repository commit conventions and prohibition on unprompted commit/push proposals.
---

# Git Commit Policy & Conventions

Read this to understand the commit policy and message conventions for `coffee-chan`.

## Prohibition on Unprompted Commit/Push Proposals

- **Execution is allowed**: When instructed by the user, or when creating and updating pull requests on topic branches, AI agents may execute `git commit` and `git push` directly.
- **Do NOT propose or prompt for commits or pushes**: AI agents must never prompt the user to commit or push unprompted, nor ask for confirmation (e.g., do NOT ask "Would you like me to commit and push?").
- **Do NOT include unprompted commit message proposals**: Do NOT append "Proposed commit message" or commit/push suggestion sections at the end of a response unless explicitly asked by the user.
- **NEVER push directly to `main`**: All commits and pushes must strictly target topic branches. Merging into `main` rests exclusively with the human maintainer.

## Commit Message Conventions

When creating a commit or formulating a commit message:

Follow the repository convention (see `.agents/skills/pr-workflow/SKILL.md`):

- Use Conventional Commits style prefixes (`feat:`, `fix:`, `build:`, `refactor:`, `docs:`, `test:`).
- English, imperative mood, short summary, under 72 characters, no trailing period.
- **Do NOT include issue numbers (e.g., `(#24)` or `#24`) anywhere in the commit message — neither the summary nor the body.** Issue linkage must be done exclusively in the PR Description using explicit issue-closing keywords (e.g. `Closes #24`). This matters because squash merges copy every commit message into `main`, so a `Closes #24` in a commit body can close an issue the PR was never meant to close.
- The ` (#N)` suffix GitHub appends to a squash-merge commit's summary (the PR number) is added by GitHub, not by agents, and is the one exception.

Examples:

- `feat: add sequencer event scheduler`
- `refactor: extract filter coefficients`
- `docs: update git commit guidance`
