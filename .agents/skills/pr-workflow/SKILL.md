---
name: pr-workflow
description: >-
  Use this skill when creating commits, preparing Pull Requests (PRs), formatting code, and executing pre-submission verification steps for coffee-chan.
---

# Pull Request & Commit Workflow for `coffee-chan`

This skill defines the procedures for code verification, commit creation, and pull request submission.

## 1. Mandatory Verification Steps

Before committing or opening a PR, execute the following commands and ensure all pass cleanly:

| Task | Command | Description |
| :--- | :--- | :--- |
| **Check All Formatting (treefmt)** | `treefmt --fail-on-change` | Verifies formatting across Zig, Nix, Markdown, and Shell files |
| **Format All Files (treefmt)** | `treefmt` | Auto-formats all files in the repository using treefmt |
| **Run All Tests** | `zig build test` | Executes unit tests for modules and root |
| **Build WAV Output** | `zig build` | Compiles project and generates `coffee-chan.wav` |
| **Generate Sandbox Audio** | `zig build sandbox` | Generates WAV files for experimental sandbox scripts |

## 2. Commit & PR Title Conventions

Use Conventional Commits style prefixes:

- `feat:` New synthesizer, phrase, filter, or major capability.
- `fix:` Bug fixes or corrections to audio synthesis/build logic.
- `build:` Updates to `build.zig`, `build.zig.zon`, `flake.nix`, or dependencies (`lightmix`).
- `refactor:` Code restructuring without changing output logic.
- `docs:` Updates to README, AGENTS.md, or code documentation.
- `test:` Adding or updating unit/integration tests.

**Do NOT include issue numbers (e.g., `(#24)` or `#24`) anywhere in commit messages (summary or body) or PR titles.** Issue linkage must be done exclusively in the PR Description using explicit issue-closing keywords (e.g. `Closes #24`). Squash merges copy every commit message into `main`, so a closing keyword in a commit body can close the wrong issue. The ` (#N)` suffix GitHub itself appends to squash-merge summaries is the only exception.

**Language**: Write all commit messages, PR titles, PR descriptions, and repository documentation strictly in English. Never use Japanese or any other non-English language.

## 3. PR Description Requirements

Ensure the PR description includes:

- **Summary**: Concise overview of changes.
- **Linked Issue / Closes Statement**: Always include an explicit issue-closing keyword (e.g. `Closes #16`, `Fixes #12`, or `Resolves #5`) when resolving an open issue.
- **Verification**: Explicitly list executed verification commands (`treefmt --fail-on-change`, `zig build test`, etc.) and their success status.
- **Breaking Changes**: Highlight any breaking changes to modules or dependencies.

## 4. GitHub Projects Integration

When creating PRs and issues or updating project attributes in GitHub Projects (Projects v2):

- **Assign Project Attributes**: When creating a PR or issue, always assign the `Estimate`, `Priority`, and `Size` fields in GitHub Projects.
- Follow the [`github-projects`](../github-projects/SKILL.md) skill.
- Inspect the project schema (`gh project field-list`) before attempting to set field values.
- Never pass multiple `--field` and `--value` pairs in a single `gh project item-edit` command; invoke the command once per field.
- **Explicit Milestone Assignment Only**: AI agents **MUST NEVER** automatically attach or set GitHub Milestones on Pull Requests or Issues unless explicitly requested or instructed by the user.

## 5. Strict Safety & Approval Rules

- **NEVER MERGE PULL REQUESTS**: AI agents **MUST NEVER** merge PRs (including enabling auto-merge with `gh pr merge --auto`), execute `git merge` into `main`, or directly push commits to the `main` branch autonomously.
- **NEVER PROPOSE COMMITS OR PUSHES UNPROMPTED**: AI agents **MUST NEVER** prompt the user to commit or push unprompted. When instructed by the user or when preparing pull requests on topic branches, agents may execute `git commit` and `git push` directly.
- **Mandatory Human Approval**: AI agents may create branches, create commits, push topic branches, propose PRs, format code, and run test suites, but the final action of merging changes into `main` rests strictly with the human maintainer.
