//! How long a note is written to last, in beats. Resolves to a length in frames.
//!
//! This is the default duration primitive. The conversion from beats to frames happens here, in
//! `resolve`, through the same rounding as `Timing`, so `Layer` never reads a duration specially.

const std = @import("std");
const Context = @import("./context.zig");
const tempo = @import("./tempo.zig");

const Self = @This();

/// Written length in beats of the time signature; must be finite and not negative.
beats: f64,

/// A length in frames.
pub const ResolveT = usize;

/// Resolves this duration to a length in frames, rounded to the nearest frame. The origin of the
/// segment does not change a length, so `ctx.origin` is ignored. Returns `error.InvalidDuration`
/// for beats that are NaN, negative or infinite or a length beyond a `usize`, and a `tempo.Error`
/// for an invalid context.
pub fn resolve(self: Self, ctx: Context) (error{InvalidDuration} || tempo.Error)!ResolveT {
    const spb = try tempo.samplesPerBeat(ctx.bpm, ctx.time_signature, ctx.sample_rate);
    return tempo.framesFromBeats(self.beats, spb) orelse error.InvalidDuration;
}

test "resolve converts beats to frames" {
    // 140 BPM, 44100 Hz: a beat is 18900 frames, a 16th note 4725 frames.
    const ctx: Context = .{ .bpm = 140, .sample_rate = 44100 };
    try std.testing.expectEqual(@as(usize, 9450), try (Self{ .beats = 0.5 }).resolve(ctx));
    try std.testing.expectEqual(@as(usize, 4725), try (Self{ .beats = 0.25 }).resolve(ctx));
}

test "resolve ignores the origin" {
    const ctx: Context = .{ .bpm = 140, .sample_rate = 44100, .origin = 12.0 };
    try std.testing.expectEqual(@as(usize, 18900), try (Self{ .beats = 1.0 }).resolve(ctx));
}

test "resolve rejects invalid lengths" {
    const ctx: Context = .{ .bpm = 140, .sample_rate = 44100 };
    try std.testing.expectError(error.InvalidDuration, (Self{ .beats = -1.0 }).resolve(ctx));
    try std.testing.expectError(error.InvalidDuration, (Self{ .beats = std.math.nan(f64) }).resolve(ctx));
}

test {
    std.testing.refAllDecls(@This());
}
