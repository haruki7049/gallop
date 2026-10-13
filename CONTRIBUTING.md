# Contributing Guide for `gallop`

Thank you for contributing to `gallop`! This document outlines the development guidelines, setup instructions, and code verification workflow for contributors.

______________________________________________________________________

## 1. Project Overview & Architecture

`gallop` is a deterministic music generation project built using Zig `0.16.0` and the [`lightmix`](https://github.com/haruki7049/lightmix) audio synthesis library. It produces a piece of music about one minute long, based on a gallop rhythm, with a timbre planned to be rock-styled.

- **Deterministic Music Generation**: Running build steps generates `.wav` audio files directly during the build process without real-time recording.
- **Modular Audio Architecture**: Code is structured into reusable modules under `modules/`, one per role, and connected in `src/root.zig`. See [Module Boundaries](#module-boundaries).
- **Sandbox Environment**: Experimental synthesizers, scales, and audio prototypes reside in `sandbox/`.

______________________________________________________________________

## 2. Development Environment Setup

We manage project dependencies using **Nix**, **direnv**, and **nix-direnv** for reproducible development environments.

### Prerequisites

- [Nix](https://nixos.org/download.html) with Flakes enabled
- [direnv](https://direnv.net/)

### Quick Start

```bash
# Clone the repository
git clone https://github.com/haruki7049/gallop.git
cd gallop

# Allow direnv to load the Nix development shell automatically
direnv allow
```

Once inside the environment, all required tools (`zig`, `treefmt`, `zon2nix`, etc.) are automatically placed in your path.

______________________________________________________________________

## 3. Repository Structure

- `src/`: Main entry point (`root.zig`) for composing the full track, the primitives of the piece (`primitives.zig`), the scores (`scores.zig`), the instrument set (`instruments.zig`), and song-wide constants (`configs.zig`).
- `modules/`: Reusable building blocks, one module per role:
  - `pitch/`: Pitch names, transposition and tuning.
  - `score/`: Score information: primitives, zip, concatenation, resolution to values.
  - `body/`: The rule of a vibrating body: decides the approximation fade from starts and lengths.
  - `perform/`: The procedure that turns values into waveforms, and the instrument-set type.
  - `mix/`: Place and mix: applies the approximation fade, places and mixes waveforms.
  - `timbre/`: Ready-made timbres that return plain sample arrays.
- `sandbox/`: Experimental scripts for audio prototyping (not created yet).
- `.github/workflows/`: CI/CD automation workflows.

### Module Boundaries

- Every module under `modules/` imports nothing but `std`, neither `lightmix` nor another module. `build.zig` creates each module with no `imports`, so a forbidden `@import` fails to compile.
- A module that needs another module's type receives it as a comptime parameter.
- Modules exchange values and plain slices only. No module returns or accepts `lightmix.Wave`.
- The piece's module, rooted at `src/root.zig`, is the only module that imports `lightmix` and the modules. The boundary is per module, not per file: every file under `src/` belongs to that module.
- Each module has its own tests, run by `zig build test` without the others.
- No hidden global state: anything random takes an explicitly seeded generator.

______________________________________________________________________

## 4. Mandatory Verification Workflow

Before creating a Pull Request, you **MUST** run all verification commands and ensure clean execution:

| Command | Purpose |
| :--- | :--- |
| `treefmt` | Formats all files across Zig, Nix, Markdown, and Shell |
| `treefmt --fail-on-change` | Checks formatting compliance across all project files |
| `zig build` | Compiles the main project and generates `gallop.wav` |
| `zig build test` | Executes unit test suites across all modules and root |
| `zig build sandbox` | Generates WAV outputs for experimental sandbox scripts |

______________________________________________________________________

## 5. Naming Conventions

All code symbols, directory layouts, music track arrangements, Git branches, and commit messages follow our centralized naming standards. Please refer to [Naming Conventions](docs/NAMING.md) for detailed rules and examples before submitting contributions.

______________________________________________________________________

## 6. Pull Request Guidelines

1. **Format & Test Verification**: Ensure `treefmt --fail-on-change`, `zig build`, `zig build test`, and `zig build sandbox` all pass cleanly.
1. **Conventional Commits**: Use conventional commit prefixes (`feat:`, `fix:`, `docs:`, `refactor:`, `build:`, `test:`, `ci:`).
1. **PR Description**: Include a clear summary of changes, an explicit issue-closing keyword (e.g., `Closes #123`), and confirmation of completed verification commands.
