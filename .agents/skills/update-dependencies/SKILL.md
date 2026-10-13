---
name: update-dependencies
description: >-
  Use this skill when updating external Zig package dependencies (such as lightmix), synchronizing Nix lockfiles (.deps.nix via zon2nix), or modifying build.zig.zon.
---

# External Dependency Update Workflow (`lightmix`)

When updating external dependencies such as `lightmix`, both `build.zig.zon` and `.deps.nix` must be kept in sync:

1. **Update `build.zig.zon`**: Update the `url` (and package hash) under `.dependencies.lightmix`.
1. **Synchronize Nix Lockfile**: Run `zon2nix > .deps.nix` to regenerate the Nix dependency lockfile `.deps.nix`.
1. **Fix Archive URLs**: `zon2nix` emits extensionless `https://codeload.github.com/<owner>/<repo>/tar.gz/refs/tags/<tag>` URLs, which `fetchzip` cannot unpack on a clean store (it picks the unpack method from the file name). Rewrite each one to the `https://github.com/<owner>/<repo>/archive/refs/tags/<tag>.tar.gz` form used in `build.zig.zon`. Keep the generated hashes; both URLs serve identical tarballs. See haruki7049/zigggwavvv#85.
1. **Format Code**: Run `treefmt` to format all changed files (including `.deps.nix` and `build.zig.zon`).
1. **Verification**: Run `zig build`, `zig build test`, and `zig build sandbox` to guarantee error-free compilation and execution. Also run `nix build --print-build-logs`. A fixed-output derivation is skipped when the store already holds its result, so a warm store can hide a broken `.deps.nix`; when practical, verify on a clean store (`nix-collect-garbage -d` first) or rely on CI.
