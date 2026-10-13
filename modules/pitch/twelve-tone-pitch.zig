//! Twelve-tone pitch: one of the 12 pitch classes and an octave. Holds no tuning.

const std = @import("std");

const Self = @This();

/// Pitch class.
code: Code,
/// Octave number in scientific pitch notation: C4 is middle C and A4 is the A above it.
/// Negative octaves go below C0: C-1 is MIDI note 0. The range is C-128 to B127.
octave: i8,

/// Pitch class codes in ascending order, from `c` (0) to `b` (11). The `s` suffix marks a sharp.
pub const Code = enum(u8) { c, cs, d, ds, e, f, fs, g, gs, a, as, b };

/// The lowest pitch, C-128 (MIDI note number -1524).
pub const lowest: Self = .{ .code = .c, .octave = std.math.minInt(i8) };
/// The highest pitch, B127 (MIDI note number 1547).
pub const highest: Self = .{ .code = .b, .octave = std.math.maxInt(i8) };

/// MIDI note number: `12 * (octave + 1) + code`. C-1 is 0, C4 is 60, A4 is 69 and G9 is 127.
///
/// The numbering extends past the MIDI range 0-127 in both directions, from -1524 (C-128) to
/// 1547 (B127), so it always fits in an `i16`.
pub fn midi(self: Self) i16 {
    return 12 * (@as(i16, self.octave) + 1) + @intFromEnum(self.code);
}

/// Returns the pitch of a MIDI note number, the inverse of `midi`.
/// Returns `error.PitchOutOfRange` outside -1524 (C-128) to 1547 (B127).
pub fn fromMidi(number: i16) error{PitchOutOfRange}!Self {
    if (number < lowest.midi() or number > highest.midi()) return error.PitchOutOfRange;
    return .{
        .code = @enumFromInt(@mod(number, 12)),
        .octave = @intCast(@divFloor(number, 12) - 1),
    };
}

/// Transposes by `semitones` (negative goes down).
/// Returns `error.PitchOutOfRange` when the result falls outside C-128 to B127.
pub fn add(self: Self, semitones: isize) error{PitchOutOfRange}!Self {
    const result = std.math.add(isize, self.midi(), semitones) catch return error.PitchOutOfRange;
    return fromMidi(std.math.cast(i16, result) orelse return error.PitchOutOfRange);
}

test "midi at reference pitches and range boundaries" {
    // C-128 = 12 * (-128 + 1) + 0 = -1524, the lowest pitch
    try std.testing.expectEqual(@as(i16, -1524), lowest.midi());
    // C-2 = 12 * (-2 + 1) + 0 = -12
    try std.testing.expectEqual(@as(i16, -12), (Self{ .code = .c, .octave = -2 }).midi());
    // C-1 = 12 * (-1 + 1) + 0 = 0, MIDI note 0
    try std.testing.expectEqual(@as(i16, 0), (Self{ .code = .c, .octave = -1 }).midi());
    // B-1 = 12 * (-1 + 1) + 11 = 11
    try std.testing.expectEqual(@as(i16, 11), (Self{ .code = .b, .octave = -1 }).midi());
    // C0 = 12 * (0 + 1) + 0 = 12
    try std.testing.expectEqual(@as(i16, 12), (Self{ .code = .c, .octave = 0 }).midi());
    // C4 = 12 * (4 + 1) + 0 = 60, middle C
    try std.testing.expectEqual(@as(i16, 60), (Self{ .code = .c, .octave = 4 }).midi());
    // A4 = 12 * (4 + 1) + 9 = 69
    try std.testing.expectEqual(@as(i16, 69), (Self{ .code = .a, .octave = 4 }).midi());
    // G9 = 12 * (9 + 1) + 7 = 127, the top of the MIDI range
    try std.testing.expectEqual(@as(i16, 127), (Self{ .code = .g, .octave = 9 }).midi());
    // B127 = 12 * (127 + 1) + 11 = 1547, the highest pitch
    try std.testing.expectEqual(@as(i16, 1547), highest.midi());
}

test "midi counts codes in ascending semitones within an octave" {
    // Octave -1 starts at 0 and octave 4 at 60, so code i is 0 + i and 60 + i.
    for (std.enums.values(Code)) |code| {
        const i: i16 = @intFromEnum(code);
        try std.testing.expectEqual(i, (Self{ .code = code, .octave = -1 }).midi());
        try std.testing.expectEqual(60 + i, (Self{ .code = code, .octave = 4 }).midi());
    }
}

test "fromMidi at range boundaries" {
    try std.testing.expectEqual(lowest, try fromMidi(-1524));
    // -13 = 12 * (-2 + 1) - 1, B-3
    try std.testing.expectEqual(Self{ .code = .b, .octave = -3 }, try fromMidi(-13));
    try std.testing.expectEqual(Self{ .code = .c, .octave = -2 }, try fromMidi(-12));
    // -1 = 12 * (-1 + 1) - 1, B-2
    try std.testing.expectEqual(Self{ .code = .b, .octave = -2 }, try fromMidi(-1));
    try std.testing.expectEqual(Self{ .code = .c, .octave = -1 }, try fromMidi(0));
    try std.testing.expectEqual(Self{ .code = .b, .octave = -1 }, try fromMidi(11));
    try std.testing.expectEqual(Self{ .code = .c, .octave = 0 }, try fromMidi(12));
    try std.testing.expectEqual(Self{ .code = .g, .octave = 9 }, try fromMidi(127));
    // 128 = 12 * (9 + 1) + 8, G#9, the first number beyond the MIDI range
    try std.testing.expectEqual(Self{ .code = .gs, .octave = 9 }, try fromMidi(128));
    try std.testing.expectEqual(highest, try fromMidi(1547));
}

test "fromMidi rejects numbers outside the range" {
    try std.testing.expectError(error.PitchOutOfRange, fromMidi(-1525));
    try std.testing.expectError(error.PitchOutOfRange, fromMidi(1548));
    try std.testing.expectError(error.PitchOutOfRange, fromMidi(std.math.minInt(i16)));
    try std.testing.expectError(error.PitchOutOfRange, fromMidi(std.math.maxInt(i16)));
}

test "midi(fromMidi(n)) is n over the whole range" {
    var n: i16 = lowest.midi();
    while (n <= highest.midi()) : (n += 1) {
        try std.testing.expectEqual(n, (try fromMidi(n)).midi());
    }
}

test "fromMidi(midi(p)) is p for every pitch" {
    var octave: i16 = std.math.minInt(i8);
    while (octave <= std.math.maxInt(i8)) : (octave += 1) {
        for (std.enums.values(Code)) |code| {
            const p = Self{ .code = code, .octave = @intCast(octave) };
            try std.testing.expectEqual(p, try fromMidi(p.midi()));
        }
    }
}

test "add moves across octave boundaries" {
    // B3 (59) + 1 = 60 = C4
    try std.testing.expectEqual(Self{ .code = .c, .octave = 4 }, try (Self{ .code = .b, .octave = 3 }).add(1));
    // A4 (69) + 3 = 72 = C5
    try std.testing.expectEqual(Self{ .code = .c, .octave = 5 }, try (Self{ .code = .a, .octave = 4 }).add(3));
    // E4 (64) - 7 = 57 = A3
    try std.testing.expectEqual(Self{ .code = .a, .octave = 3 }, try (Self{ .code = .e, .octave = 4 }).add(-7));
    // C0 (12) - 1 = 11 = B-1, into the negative octaves
    try std.testing.expectEqual(Self{ .code = .b, .octave = -1 }, try (Self{ .code = .c, .octave = 0 }).add(-1));
    // C-1 (0) - 1 = -1 = B-2, below MIDI note 0
    try std.testing.expectEqual(Self{ .code = .b, .octave = -2 }, try (Self{ .code = .c, .octave = -1 }).add(-1));
    // B-2 (-1) + 1 = 0 = C-1
    try std.testing.expectEqual(Self{ .code = .c, .octave = -1 }, try (Self{ .code = .b, .octave = -2 }).add(1));
}

test "add by whole octaves keeps the code" {
    const fs4 = Self{ .code = .fs, .octave = 4 };
    try std.testing.expectEqual(Self{ .code = .fs, .octave = 5 }, try fs4.add(12));
    try std.testing.expectEqual(Self{ .code = .fs, .octave = 3 }, try fs4.add(-12));
    // F#4 (66) - 72 = -6 = 12 * (-2 + 1) + 6, F#-2
    try std.testing.expectEqual(Self{ .code = .fs, .octave = -2 }, try fs4.add(-72));
    // F#4 (66) + 120 = 186 = 12 * (14 + 1) + 6, F#14
    try std.testing.expectEqual(Self{ .code = .fs, .octave = 14 }, try fs4.add(120));
}

test "add by zero is the identity" {
    for (std.enums.values(Code)) |code| {
        inline for (.{ -128, -1, 0, 4, 127 }) |octave| {
            const p = Self{ .code = code, .octave = octave };
            try std.testing.expectEqual(p, try p.add(0));
        }
    }
}

test "add(n) then add(-n) returns the original pitch" {
    const c4 = Self{ .code = .c, .octave = 4 };
    // C4 is 60; every n in [-1584, 1487] keeps 60 + n within [-1524, 1547].
    var n: isize = -1584;
    while (n <= 1487) : (n += 1) {
        try std.testing.expectEqual(c4, try (try c4.add(n)).add(-n));
    }
}

test "add reaches both ends of the range but not beyond" {
    // C4 (60) - 1584 = -1524 = C-128
    try std.testing.expectEqual(lowest, try (Self{ .code = .c, .octave = 4 }).add(-1584));
    try std.testing.expectError(error.PitchOutOfRange, (Self{ .code = .c, .octave = 4 }).add(-1585));
    try std.testing.expectError(error.PitchOutOfRange, lowest.add(-1));
    // C4 (60) + 1487 = 1547 = B127
    try std.testing.expectEqual(highest, try (Self{ .code = .c, .octave = 4 }).add(1487));
    try std.testing.expectError(error.PitchOutOfRange, (Self{ .code = .c, .octave = 4 }).add(1488));
    try std.testing.expectError(error.PitchOutOfRange, highest.add(1));
}

test "add rejects the extremes of isize without overflowing" {
    const c4 = Self{ .code = .c, .octave = 4 };
    try std.testing.expectError(error.PitchOutOfRange, c4.add(std.math.maxInt(isize)));
    try std.testing.expectError(error.PitchOutOfRange, c4.add(std.math.minInt(isize)));
    try std.testing.expectError(error.PitchOutOfRange, highest.add(std.math.maxInt(isize)));
    try std.testing.expectError(error.PitchOutOfRange, lowest.add(std.math.minInt(isize)));
}

test "a negative octave coerces from a ZON-shaped literal" {
    const p: Self = .{ .code = .a, .octave = -1 };
    // A-1 = 12 * (-1 + 1) + 9 = 9
    try std.testing.expectEqual(@as(i16, 9), p.midi());
}

test {
    std.testing.refAllDecls(@This());
}
