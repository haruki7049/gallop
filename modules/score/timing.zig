//! When a note starts: a bar and a beat. Resolves to a frame position.
//!
//! This is the default timing primitive; it keeps the same contract as any other primitive. A
//! beat at or past the numerator of the time signature carries into the following bars: in 4/4,
//! bar 0 beat 5 is the same position as bar 1 beat 1.

const std = @import("std");
const Context = @import("./context.zig");
const tempo = @import("./tempo.zig");

const Self = @This();

/// 0-indexed bar, counted from the start of the segment the element was written in.
bar: usize = 0,
/// Beat offset from the start of `bar`; must be finite and not negative.
beat: f64 = 0.0,

/// A frame position, counted from the start of the score.
pub const ResolveT = usize;

/// Resolves this timing to a frame position: `ctx.origin` beats, plus `bar` bars, plus `beat`
/// beats, rounded to the nearest frame once. Returns `error.InvalidPosition` for a beat that is
/// NaN, negative or infinite or a position beyond a `usize`, and a `tempo.Error` for an invalid
/// context.
pub fn resolve(self: Self, ctx: Context) (error{InvalidPosition} || tempo.Error)!ResolveT {
    // Written as a negation so that NaN is rejected too; infinity is caught below.
    if (!(self.beat >= 0.0)) return error.InvalidPosition;

    const spb = try tempo.samplesPerBeat(ctx.bpm, ctx.time_signature, ctx.sample_rate);
    const numerator: f64 = @floatFromInt(ctx.time_signature.numerator);
    const beats = ctx.origin + @as(f64, @floatFromInt(self.bar)) * numerator + self.beat;
    return tempo.framesFromBeats(beats, spb) orelse error.InvalidPosition;
}

test "resolve counts bars and beats in 4/4" {
    // 60 BPM, 44100 Hz: a beat is 44100 frames. Bar 1 beat 2 is 6 beats.
    const timing: Self = .{ .bar = 1, .beat = 2.0 };
    try std.testing.expectEqual(@as(usize, 264600), try timing.resolve(.{ .bpm = 60, .sample_rate = 44100 }));
}

test "resolve carries a beat past the numerator into the next bar" {
    const ctx: Context = .{ .bpm = 60, .sample_rate = 44100 };
    const carried: Self = .{ .bar = 0, .beat = 5.0 };
    const written: Self = .{ .bar = 1, .beat = 1.0 };
    try std.testing.expectEqual(try written.resolve(ctx), try carried.resolve(ctx));
}

test "resolve adds the origin of the segment" {
    // 120 BPM, 44100 Hz: a beat is 22050 frames. Origin 4 plus beat 0.5 is 4.5 beats.
    const timing: Self = .{ .beat = 0.5 };
    try std.testing.expectEqual(@as(usize, 99225), try timing.resolve(.{ .bpm = 120, .sample_rate = 44100, .origin = 4.0 }));
}

test "resolve rejects invalid beats and contexts" {
    const ctx: Context = .{ .bpm = 120, .sample_rate = 44100 };
    try std.testing.expectError(error.InvalidPosition, (Self{ .beat = -0.25 }).resolve(ctx));
    try std.testing.expectError(error.InvalidPosition, (Self{ .beat = std.math.nan(f64) }).resolve(ctx));
    try std.testing.expectError(error.InvalidPosition, (Self{ .beat = std.math.inf(f64) }).resolve(ctx));
    try std.testing.expectError(error.InvalidBpm, (Self{}).resolve(.{ .bpm = 0, .sample_rate = 44100 }));
}

test {
    std.testing.refAllDecls(@This());
}
