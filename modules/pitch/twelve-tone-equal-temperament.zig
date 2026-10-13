//! Twelve-tone equal temperament (12-TET) tuning referenced to A4.

const std = @import("std");
const TwelveTonePitch = @import("./twelve-tone-pitch.zig");

const Self = @This();

/// Frequency of A4 in Hz, such as 440.0 (the default), 442.0 or 432.0.
/// It must be positive and finite; `freq` does not check it.
a4: f64 = 440.0,

/// Frequency in Hz: `a4 * 2^((midi - 69) / 12)`.
///
/// Each semitone multiplies the frequency by `2^(1/12)` and each octave doubles it exactly. Over
/// the whole range of `TwelveTonePitch`, from C-128 (about 4.8e-38 Hz at A4 = 440 Hz) to B127 (about
/// 5.3e39 Hz), the result is a normal `f64` within a few units in the last place.
pub fn freq(self: Self, pitch: TwelveTonePitch) f64 {
    // Split the distance from A4 into whole octaves and the semitones left within an octave.
    // Only the semitones go through `pow`, with an exponent in [0, 11/12], so its rounding does not
    // grow with the distance; the octaves scale the result exactly through `ldexp`.
    const semitones_from_a4: i32 = @as(i32, pitch.midi()) - 69;
    const octaves = @divFloor(semitones_from_a4, 12);
    const semitones: f64 = @floatFromInt(@mod(semitones_from_a4, 12));
    return std.math.ldexp(self.a4 * std.math.pow(f64, 2.0, semitones / 12.0), octaves);
}

test "freq at A4 = 440 Hz against reference values" {
    const et: Self = .{};
    // A4 is the reference itself.
    try std.testing.expectEqual(@as(f64, 440.0), et.freq(.{ .code = .a, .octave = 4 }));
    // A0 = 440 * 2^(-48/12) = 440 / 16 = 27.5 Hz, exactly
    try std.testing.expectEqual(@as(f64, 27.5), et.freq(.{ .code = .a, .octave = 0 }));
    // The values below are 440 * 2^(k/12) computed with `bc -l`, k = midi - 69.
    // C0: k = -57
    try std.testing.expectApproxEqRel(@as(f64, 16.351597831287414667), et.freq(.{ .code = .c, .octave = 0 }), 1e-15);
    // G3: k = -14
    try std.testing.expectApproxEqRel(@as(f64, 195.99771799087463), et.freq(.{ .code = .g, .octave = 3 }), 1e-15);
    // C4: k = -9
    try std.testing.expectApproxEqRel(@as(f64, 261.62556530059863467), et.freq(.{ .code = .c, .octave = 4 }), 1e-15);
    // C8: k = 39
    try std.testing.expectApproxEqRel(@as(f64, 4186.0090448095781548), et.freq(.{ .code = .c, .octave = 8 }), 1e-15);
    // B9: k = 62
    try std.testing.expectApproxEqRel(@as(f64, 15804.265640195971578), et.freq(.{ .code = .b, .octave = 9 }), 1e-15);
}

test "freq in negative octaves against reference values" {
    const et: Self = .{};
    // A-1 = 440 * 2^(-60/12) = 440 / 32 = 13.75 Hz, exactly
    try std.testing.expectEqual(@as(f64, 13.75), et.freq(.{ .code = .a, .octave = -1 }));
    // The values below are 440 * 2^(k/12) computed with `bc -l`, k = midi - 69.
    // C-1 (MIDI 0): k = -69
    try std.testing.expectApproxEqRel(@as(f64, 8.1757989156437073337), et.freq(.{ .code = .c, .octave = -1 }), 1e-15);
    // C-2 (MIDI -12): k = -81
    try std.testing.expectApproxEqRel(@as(f64, 4.0878994578218536668), et.freq(.{ .code = .c, .octave = -2 }), 1e-15);
    // C-128 (MIDI -1524): k = -1593
    try std.testing.expectApproxEqRel(@as(f64, 4.805302719399080949897e-38), et.freq(TwelveTonePitch.lowest), 1e-15);
    // B127 (MIDI 1547): k = 1478
    try std.testing.expectApproxEqRel(@as(f64, 5.2518680854425254172e39), et.freq(TwelveTonePitch.highest), 1e-15);
}

test "freq follows a 442 Hz reference" {
    const et: Self = .{ .a4 = 442.0 };
    try std.testing.expectEqual(@as(f64, 442.0), et.freq(.{ .code = .a, .octave = 4 }));
    // A5 = 442 * 2^(12/12) = 884 Hz, exactly
    try std.testing.expectEqual(@as(f64, 884.0), et.freq(.{ .code = .a, .octave = 5 }));
}

test "freq follows a 432 Hz reference" {
    const et: Self = .{ .a4 = 432.0 };
    try std.testing.expectEqual(@as(f64, 432.0), et.freq(.{ .code = .a, .octave = 4 }));
    // A3 = 432 * 2^(-12/12) = 216 Hz, exactly
    try std.testing.expectEqual(@as(f64, 216.0), et.freq(.{ .code = .a, .octave = 3 }));
    // C4 = 432 * 2^(-9/12) = 256.8687368405877504 Hz (`bc -l`)
    try std.testing.expectApproxEqRel(@as(f64, 256.86873684058775041), et.freq(.{ .code = .c, .octave = 4 }), 1e-15);
    // C0 = 432 * 2^(-57/12) = 16.0542960525367344 Hz (`bc -l`)
    try std.testing.expectApproxEqRel(@as(f64, 16.054296052536734401), et.freq(.{ .code = .c, .octave = 0 }), 1e-15);
}

test "freq scales linearly with the reference" {
    // Every pitch at 432 Hz is 432 / 440 of the same pitch at 440 Hz.
    const et440: Self = .{};
    const et432: Self = .{ .a4 = 432.0 };
    var n: i16 = TwelveTonePitch.lowest.midi();
    while (n <= TwelveTonePitch.highest.midi()) : (n += 1) {
        const p = try TwelveTonePitch.fromMidi(n);
        try std.testing.expectApproxEqRel(et440.freq(p) * (432.0 / 440.0), et432.freq(p), 1e-15);
    }
}

test "adjacent semitones differ by 2^(1/12) over the whole range" {
    // 2^(1/12) = 1.0594630943592952646 (`bc -l`)
    const ratio: f64 = 1.0594630943592952646;
    inline for (.{ 440.0, 432.0 }) |a4| {
        const et: Self = .{ .a4 = a4 };
        var n: i16 = TwelveTonePitch.lowest.midi();
        while (n < TwelveTonePitch.highest.midi()) : (n += 1) {
            const lower = et.freq(try TwelveTonePitch.fromMidi(n));
            const upper = et.freq(try TwelveTonePitch.fromMidi(n + 1));
            try std.testing.expectApproxEqRel(ratio, upper / lower, 1e-15);
        }
    }
}

test "each octave doubles the frequency over the whole range" {
    inline for (.{ 440.0, 432.0 }) |a4| {
        const et: Self = .{ .a4 = a4 };
        var n: i16 = TwelveTonePitch.lowest.midi();
        while (n + 12 <= TwelveTonePitch.highest.midi()) : (n += 1) {
            const lower = et.freq(try TwelveTonePitch.fromMidi(n));
            const upper = et.freq(try TwelveTonePitch.fromMidi(n + 12));
            try std.testing.expectEqual(@as(f64, 2.0), upper / lower);
        }
    }
}

test "freq is a normal f64 and rises strictly over the whole range" {
    const et: Self = .{};
    var previous: f64 = 0.0;
    var n: i16 = TwelveTonePitch.lowest.midi();
    while (n <= TwelveTonePitch.highest.midi()) : (n += 1) {
        const current = et.freq(try TwelveTonePitch.fromMidi(n));
        try std.testing.expect(std.math.isNormal(current));
        try std.testing.expect(current > previous);
        previous = current;
    }
}

test {
    std.testing.refAllDecls(@This());
}
