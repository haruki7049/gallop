# Naming Conventions for `gallop`

This document defines standardized naming conventions across all layers of the `gallop` repository, including Zig source code, directory structures, music domain concepts, and Git workflow conventions.

All contributors and AI agents must follow these conventions to ensure codebase consistency, maintainability, and clarity.

______________________________________________________________________

## 1. Zig Code Symbols

Follow official Zig style guidelines augmented by repository patterns:

| Target | Convention | Example | Notes |
| :--- | :--- | :--- | :--- |
| **Types & Structs** | `PascalCase` | `Sequencer`, `Track`, `Instrument`, `VoiceScheduler`, `Renderer`, `TimeSignature` | Core data models and interfaces |
| **Generic Type Factory** | `inner(comptime T: type) type` | `pub fn inner(comptime T: type) type` | Used in leaf module files (`track.zig`, `renderer.zig`, etc.) |
| **Exported Type Alias** | `PascalCase` | `pub const Track = @import("track.zig").inner;` | Re-exported in module's `root.zig` |
| **Exported Function Alias** | `camelCase` | `pub const decay = @import("./decay.zig").inner;` | A re-exported function (such as a filter) is named like a function, not a type |
| **File Struct** | `PascalCase` | `pub const KarplusStrong = @import("./karplus-strong.zig");` | A whole file imported as a struct is named like a type |
| **Module Namespace** | `snake_case` | `pub const karplus_strong = @import("./karplus-strong/root.zig");`, `music.position` | A `root.zig` imported as a namespace; the snake_case form of the kebab-case directory name |
| **Functions & Methods** | `camelCase` (verb-focused) | `add`, `render`, `load`, `computeGain`, `mixEvent` | Prefer a concise verb when receiver context is evident; avoid repeating type names |
| **Variables & Parameters** | `snake_case` | `sample_rate`, `time_signature`, `active_frames`, `fade_frames`, `enable_attack_fade` | Descriptive names; avoid single-letter variables except loop counters (`i`, `j`, `k`) |
| **Struct Fields** | `snake_case` | `name`, `events`, `start_frame`, `wave_frames` | Keep uniform with variable names |
| **Comptime Type Parameters** | Single uppercase character | `comptime T: type`, `comptime U: type` | When receiving a type via comptime, always use a single uppercase character (`T`, `U`, etc.); multi-character names are prohibited |
| **Global Constants** | `SCREAMING_SNAKE_CASE` or `PascalCase` | `BPM`, `SAMPLE_RATE`, `CHANNELS` | Build-time or compile-time constants |
| **Enum Types** | `PascalCase` | `Position`, `Note.Code` | Enum declarations |
| **Enum Tags** | `snake_case` | `.c`, `.c_sharp`, `.d`, `.bar`, `.beat` | Lowercase with underscores for accidentals |
| **Error Sets & Tags** | `PascalCase` | `error.EmptySong`, `error.IncompatibleWaveFormat` | Standard Zig error convention |

### Verb-Only Function and Method Naming (Contextual Conciseness)

When the receiver struct, namespace, or surrounding context already makes the operand evident, functions and methods should be named using just a concise verb, avoiding redundant type repetition ("type stuttering"):

- **Rule**: If the operand or target of the action is obvious from the struct type or method receiver, omit the type name from the method name.
- **Examples**:
  - Prefer `Track.add(wave, pos)` over `Track.addWave(wave, pos)`.
  - Prefer `Wave.add(...)` over `Wave.addWave(...)`.
  - Prefer `Sequencer.render()` over `Sequencer.renderAudio()`.
- **Disambiguation Exception**: Retain a trailing noun only when necessary to disambiguate between multiple distinct entities that can be acted on by the same receiver (e.g. `Sequencer.createTrack` vs. `Sequencer.createInstrument`).

```zig
// Preferred: Context provides the operand, verb-only method
pub fn add(self: *Self, wave: lightmix.Wave(T), position: Position) !void { ... }
pub fn render(self: *Self) !lightmix.Wave(T) { ... }
pub fn schedule(allocator: std.mem.Allocator, ...) ![]ScheduledEvent { ... }

// Discouraged: Redundant type name repeating the receiver or parameter context
pub fn addWave(self: *Self, wave: lightmix.Wave(T), ...) !void { ... } // Redundant "Wave"
pub fn renderAudio(self: *Self) !lightmix.Wave(T) { ... } // Redundant "Audio"
```

### Comptime Type Parameters (Single-Character Rule)

When a function, struct, or factory accepts a type at compile time via `comptime`:

- **Single Uppercase Character**: Type parameters must **always** be defined as a single uppercase character:
  - Primary type parameter: `T` (e.g. sample or element type `f64`/`f32`).
  - Additional type parameters: `U`, `V`, `S`, etc., if multiple types are accepted.
- **Prohibition**: Multi-character names for comptime type parameters (such as `comptime SampleType: type`, `comptime FloatType: type`, or `comptime Item: type`) are strictly prohibited.
- **Rationale**: Keeps generic definitions concise and readable, adheres to standard Zig and mathematical conventions, and clearly distinguishes generic type parameters from concrete types (`PascalCase`) and runtime parameters (`snake_case`).

```zig
// Correct: Single uppercase character
pub fn inner(comptime T: type) type { ... }
pub fn load(comptime T: type, seq: *Sequencer(T), start_bar: usize) !void { ... }
pub fn mix(comptime T: type, comptime U: type, input: []const T) []U { ... }

// Incorrect: Multi-character type parameter names
pub fn inner(comptime SampleType: type) type { ... } // Prohibited
pub fn load(comptime FloatType: type, ...) !void { ... } // Prohibited
```

### Comptime Generic Factory Pattern

When defining a type parameterized by audio sample type `T`:

1. Define the type factory as `pub fn inner(comptime T: type) type` within its implementation file (e.g. `track.zig`).
1. In the parent or module entry point (`root.zig`), alias the factory to its canonical `PascalCase` name:
   ```zig
   pub const Track = @import("track.zig").inner;
   pub const Sequencer = @import("sequencer.zig").inner;
   ```

______________________________________________________________________

## 2. Files & Directory Layout

All filenames and directories must be ASCII lowercase kebab-case to maintain cross-platform compatibility:

| Layer | Convention | Example | Notes |
| :--- | :--- | :--- | :--- |
| **Source Files** | `kebab-case.zig` | `voice-scheduler.zig`, `time-signature.zig`, `renderer.zig` | Module source implementations, including `sandbox/`; named after the type or namespace they define (sandbox files after the WAV they produce) |
| **Module Root** | `root.zig` | `modules/sequencer/root.zig` | Package/module public entry point |
| **Module Directories** | `kebab-case/` | `modules/filters/`, `modules/synthesizers/karplus-strong/`, `modules/synthesizers/wood-bass/` | Category and module grouping; the Zig namespace for a directory stays `snake_case` (`karplus_strong`) |
| **Phrase Directories** | `0000/` (4-digit zero-padded) | `modules/phrases/0000/`, `modules/phrases/0001/` | Sequential phrase numbering |
| **Phrase Metadata** | `phrase.zon` | `modules/phrases/0000/phrase.zon` | Declarative score and phrase metadata |
| **Phrase Re-export** | `_<4-digits>` | `pub const _0000 = Bind(@import("./0000/phrase.zon"));` | Prefixed with `_` in `modules/phrases/root.zig` for valid Zig identifier |

______________________________________________________________________

## 3. Music & Sequencer Domain

Conventions for musical abstractions, tracks, instruments, and timelines:

### Track & Instrument Naming

- **Single Instruments / Tracks**: Use descriptive `PascalCase` names:
  ```zig
  const melody_track = try seq.createTrack("Melody");
  const bass_track = try seq.createTrack("UprightBass");
  ```
- **Multi-string / Polyphonic Instruments**: Group strings under a common prefix using `<InstrumentName>/<string_index>` (0-indexed from lowest string):
  ```zig
  // createInstrument("AcousticGuitar", 6) creates:
  // "AcousticGuitar/0", "AcousticGuitar/1", ..., "AcousticGuitar/5"
  const guitar = try seq.createInstrument("AcousticGuitar", 6);
  ```
- **Percussive Tracks**: Name with instrument or role (e.g., `"Percussion/Kick"`, `"BrushDrums"`). Set `track.enable_attack_fade = false` when preserving immediate onset transients.

### Timeline & Score Representations

- **Bars**: 0-indexed integers (`bar: usize`, e.g. bar 0 is the 1st bar).
- **Beats**: 0.0-indexed floating point (`beat: f64`, e.g. `0.0` is beat 1, `1.0` is beat 2, `1.5` is the eighth-note upbeat of beat 2).
- **Note Pitch**: Defined via `Note` struct:
  - Code: `.c`, `.c_sharp`, `.d`, `.d_sharp`, `.e`, `.f`, `.f_sharp`, `.g`, `.g_sharp`, `.a`, `.a_sharp`, `.b`
  - Octave: Signed integer `i8` (e.g., `octave: 4` for middle C).
- **Phrase Functions**:
  - `toEvents`: Converts declarative ZON notes into sequenced `TrackEvent`s.
  - `load`: Sequentially attaches phrase notes to designated `Sequencer` tracks or instruments.
  - `gen`: Standalone rendering to `lightmix.Wave(T)` for unit testing and audio preview.

______________________________________________________________________

## 4. Git & Development Workflow

### Topic Branches

Branch names must use `<category>/<kebab-case-description>`:

- `feat/<feature-name>`: e.g. `feat/phrase-0003-outro`, `feat/sequencer-percussion-transient-opt-out`
- `refactor/<refactor-target>`: e.g. `refactor/sequencer-renderer`, `refactor/phrase-0001-streaming`
- `fix/<issue-name>`: e.g. `fix/sequencer-cascade-truncate`, `fix/micro-fade-bounds`
- `docs/<doc-name>`: e.g. `docs/naming-conventions`
- `test/<test-scope>`: e.g. `test/sequencer-single-string`
- `build/<build-change>`: e.g. `build/bump-lightmix`

### Commit Messages & PR Titles

- **Format**: `<type>(<scope>): <concise description in imperative mood>`
- **Types**: `feat`, `fix`, `refactor`, `docs`, `build`, `test`, `ci`
- **Scope (Optional)**: `sequencer`, `phrase`, `filter`, `synth`, `composition`
- **Rules**:
  - Strictly written in English.
  - **Never** include issue numbers in commit messages or PR titles (e.g. no `(#46)` or `#46`).
  - Keep titles under 72 characters where feasible.

### PR Descriptions & Issue Linkage

- **Issue Closing**: Always link issues via closing keywords in the PR body:
  - `Closes #123`, `Fixes #123`, or `Resolves #123`
- **Verification Table**: Include explicit pass status for required commands:
  - `treefmt --fail-on-change`
  - `zig build`
  - `zig build test`
  - `zig build sandbox`
