//! Score information: write, compose (zip, concatenation), resolve to values.
//!
//! Role: Score information. Depends on nothing but `std`.
//!
//! A score is written as layers of named primitives. A primitive is any type with `ResolveT` and
//! `resolve(self, ctx: Context)`; the user passes primitive types in, and `Layer` builds the layer
//! type from them at compile time. Zip and concatenation are written once, here. `resolve` returns,
//! per note, one named value per primitive: with the default `Timing` and `Duration` primitives,
//! a frame position (`timing`) and a length in frames (`duration`).
//!
//! This module does not create sound, mix, or decide which vibrating body sounds a note.

const std = @import("std");

/// Returns the layer type made of the given named primitives, e.g. `Layer(.{ .timing = Timing })`.
pub const Layer = @import("./layer.zig").inner;
/// Errors of `zip`.
pub const ZipError = @import("./layer.zig").ZipError;
/// Everything a primitive may need to resolve itself.
pub const Context = @import("./context.zig");
/// Beats per bar and the note value of one beat.
pub const TimeSignature = @import("./time-signature.zig");
/// Default timing primitive: a bar and a beat, resolved to a frame position.
pub const Timing = @import("./timing.zig");
/// Default duration primitive: a length in beats, resolved to a length in frames.
pub const Duration = @import("./duration.zig");
/// Conversions between beats and frames shared by `Timing` and `Duration`.
pub const tempo = @import("./tempo.zig");

test {
    std.testing.refAllDecls(@This());
}
