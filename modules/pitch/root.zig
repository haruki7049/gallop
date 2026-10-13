//! Pitch: pitch names, transposition and tuning.
//!
//! Role: Pitch. Depends on nothing but `std`.
//!
//! The name of a pitch (`TwelveTonePitch`) and its tuning (`TwelveToneEqualTemperament`) are kept
//! apart, so a score can hold names while the tuning is chosen where the names are resolved to
//! frequencies. Every public name states the pitch system it belongs to (`TwelveTone...`), so that
//! other systems can sit beside it without taking over a generic name.
//!
//! Copied from `pitches` (`src/twelve-tone-pitch.zig` and `src/twelve-tone-equal-temperament.zig`).

const std = @import("std");

/// Twelve-tone pitch: one of the 12 pitch classes (`TwelveTonePitch.Code`) and an octave.
pub const TwelveTonePitch = @import("./twelve-tone-pitch.zig");
/// Twelve-tone equal temperament (12-TET) tuning referenced to A4.
pub const TwelveToneEqualTemperament = @import("./twelve-tone-equal-temperament.zig");

test {
    std.testing.refAllDecls(@This());
}
