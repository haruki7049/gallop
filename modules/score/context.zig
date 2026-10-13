//! Everything a primitive may need to resolve itself. The same for every primitive.

const std = @import("std");
const TimeSignature = @import("./time-signature.zig");

/// Tempo in quarter notes per minute, whatever the denominator of `time_signature`.
bpm: usize,
/// Meter the beats of the score are counted in.
time_signature: TimeSignature = .{},
/// Sample rate the frame positions and lengths are counted in.
sample_rate: u32,
/// Beats from the start of the score to the start of the segment an element was written in.
///
/// `Layer.resolve` adds the origin of each element to the origin given by the caller, so a
/// primitive that places itself in time (such as `Timing`) adds it to its own position. Every
/// other primitive ignores it.
origin: f64 = 0.0,

test {
    std.testing.refAllDecls(@This());
}
