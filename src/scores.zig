//! The score of every vibrating body.
//!
//! Form: 34 bars of 4/4 at 140 BPM, about 58 seconds.
//!
//!     bars  0-3   intro    guitars on E; bass, kick and hi-hat join in bar 2
//!     bars  4-11  verse    E E C D, twice
//!     bars 12-19  lift     the verse transposed up a fourth
//!     bars 20-27  verse
//!     bars 28-31  climax   the first half of the verse transposed up a fifth
//!     bars 32-33  ending   one open chord on E
//!
//! Every vibrating body plays on the same timeline, derived from the base gallop: 128 gallops
//! and the final chord. Parts differ only in the primitives zipped onto it; a zero volume is a
//! rest.

const std = @import("std");
const score = @import("score");
const configs = @import("./configs.zig");
const primitives = @import("./primitives.zig");

const T = configs.T;
const Pitch = primitives.Pitch;
const Volume = primitives.Volume;
const Mute = primitives.Mute;
const Stroke = primitives.Stroke;
const Transpose = primitives.Transpose;

const Rhythm = score.Layer(.{ .timing = score.Timing, .duration = score.Duration });
const Volumes = score.Layer(.{ .volume = Volume });
const Mutes = score.Layer(.{ .mute = Mute });
const Strokes = score.Layer(.{ .stroke = Stroke });
const Pitches = score.Layer(.{ .pitch = Pitch });

/// Score of a drum: kick, snare or crash.
pub const Hits = score.Layer(.{ .timing = score.Timing, .duration = score.Duration, .volume = Volume });
/// Score of the hi-hat.
pub const HiHat = score.Layer(.{ .timing = score.Timing, .duration = score.Duration, .volume = Volume, .stroke = Stroke });
/// Score of the bass.
pub const BassLine = score.Layer(.{ .timing = score.Timing, .duration = score.Duration, .volume = Volume, .pitch = Pitch });
/// Score of one guitar string.
pub const GuitarLine = score.Layer(.{ .timing = score.Timing, .duration = score.Duration, .volume = Volume, .mute = Mute, .pitch = Pitch });

/// The base gallop: an eighth and two sixteenths, one beat long. Everything else is derived
/// from it.
const gallop: Rhythm = .{
    .columns = .{
        .timing = &.{ .{ .beat = 0.0 }, .{ .beat = 0.5 }, .{ .beat = 0.75 } },
        .duration = &.{ .{ .beats = 0.5 }, .{ .beats = 0.25 }, .{ .beats = 0.25 } },
    },
    .extent = 1.0,
};

/// The final chord: one note, two bars long.
const ending: Rhythm = .{
    .columns = .{ .timing = &.{.{}}, .duration = &.{.{ .beats = 8.0 }} },
    .extent = 8.0,
};

const intro_bars = 4;
const verse_bars = 8;
const climax_bars = 4;
/// Bars of gallops before the ending.
const gallop_bars = intro_bars + 3 * verse_bars + climax_bars;

const e2: Pitch = .{ .name = .{ .code = .e, .octave = 2 } };
const c3: Pitch = .{ .name = .{ .code = .c, .octave = 3 } };
const d3: Pitch = .{ .name = .{ .code = .d, .octave = 3 } };

/// One bar of volumes, written as four gallops of three notes each.
fn bar(comptime gallops: [4][3]T) [12]Volume {
    var out: [12]Volume = undefined;
    for (gallops, 0..) |notes, beat| {
        for (notes, 0..) |value, n| out[beat * 3 + n] = .{ .value = value };
    }
    return out;
}

const off = [3]T{ 0.0, 0.0, 0.0 };
/// Only the eighth of the gallop.
const quarter = [3]T{ 0.9, 0.0, 0.0 };
/// The whole gallop.
const run = [3]T{ 1.0, 0.8, 0.9 };

const silent_bar = bar(.{ off, off, off, off });
const kick_four = bar(.{ quarter, quarter, quarter, quarter });
const kick_verse = bar(.{ run, off, run, off });
const kick_drive = bar(.{ run, run, run, run });
const snare_backbeat = bar(.{ off, quarter, off, quarter });
const snare_fill = bar(.{ off, quarter, .{ 0.7, 0.6, 0.75 }, .{ 0.85, 0.9, 1.0 } });
const crash_first = bar(.{ .{ 1.0, 0.0, 0.0 }, off, off, off });
const hat_quarters = bar(.{ .{ 0.7, 0.0, 0.0 }, .{ 0.6, 0.0, 0.0 }, .{ 0.7, 0.0, 0.0 }, .{ 0.6, 0.0, 0.0 } });
const hat_gallop = bar(.{ .{ 0.75, 0.45, 0.55 }, .{ 0.7, 0.45, 0.55 }, .{ 0.75, 0.45, 0.55 }, .{ 0.7, 0.45, 0.55 } });
/// Two bars of the lift: the second ends on an open hi-hat that rings into the next downbeat.
const hat_lift = hat_gallop ++ bar(.{ .{ 0.75, 0.45, 0.55 }, .{ 0.7, 0.45, 0.55 }, .{ 0.75, 0.45, 0.55 }, .{ 0.8, 0.0, 0.0 } });
const closed_bar = [_]Stroke{.closed} ** 12;
const lift_strokes = closed_bar ++ [_]Stroke{.closed} ** 9 ++ [_]Stroke{ .open, .closed, .closed };
const chug = bar(.{ .{ 1.0, 0.7, 0.8 }, .{ 0.9, 0.7, 0.8 }, .{ 0.95, 0.7, 0.8 }, .{ 0.9, 0.7, 0.8 } });
/// Palm muting of one gallop: the eighth a little open, the sixteenths tight.
const chug_mute = [_]Mute{ .{ .amount = 0.55 }, .{ .amount = 0.9 }, .{ .amount = 0.9 } };
const climax_mute = [_]Mute{ .{ .amount = 0.3 }, .{ .amount = 0.7 }, .{ .amount = 0.7 } };

/// The type of the only primitive of a one-primitive layer `L`.
fn Column(comptime L: type) type {
    return @FieldType(L.Item, @typeInfo(L.Item).@"struct".fields[0].name);
}

/// A layer of one primitive: `values` written once, repeated `times` times.
fn pattern(comptime L: type, allocator: std.mem.Allocator, values: []const Column(L), times: usize) !L {
    var once: L = .{ .columns = undefined };
    @field(once.columns, @typeInfo(L.Item).@"struct".fields[0].name) = values;
    return once.repeat(allocator, times);
}

/// Concatenates `parts` in order.
fn join(comptime L: type, allocator: std.mem.Allocator, parts: []const L) !L {
    var result = L.empty(0.0);
    for (parts) |part| result = try result.concat(allocator, part);
    return result;
}

/// The scores of every vibrating body.
pub const Scores = struct {
    kick: Hits,
    snare: Hits,
    crash: Hits,
    hihat: HiHat,
    bass: BassLine,
    guitar_root: GuitarLine,
    guitar_fifth: GuitarLine,
};

/// Writes the score of every vibrating body with an arena-like `allocator`: nothing is freed
/// until the whole score is.
pub fn compose(allocator: std.mem.Allocator) !Scores {
    // One timeline for every body: the gallop, again and again, then the final chord.
    const timeline = try (try gallop.repeat(allocator, gallop_bars * configs.BEATS_PER_BAR)).concat(allocator, ending);

    // Roots, one per bar, every note of the bar on it. The verse is the riff twice; the lift
    // and the climax are transpositions of it.
    const riff = try join(Pitches, allocator, &.{
        try pattern(Pitches, allocator, &.{e2}, 12),
        try pattern(Pitches, allocator, &.{e2}, 12),
        try pattern(Pitches, allocator, &.{c3}, 12),
        try pattern(Pitches, allocator, &.{d3}, 12),
    });
    const verse = try riff.concat(allocator, riff);
    const roots = try join(Pitches, allocator, &.{
        try pattern(Pitches, allocator, &.{e2}, intro_bars * 12),
        verse,
        try verse.map(allocator, .pitch, Transpose{ .semitones = 5 }),
        verse,
        try riff.map(allocator, .pitch, Transpose{ .semitones = 7 }),
        try pattern(Pitches, allocator, &.{e2}, 1),
    });

    const kick = try join(Volumes, allocator, &.{
        try pattern(Volumes, allocator, &silent_bar, 2),
        try pattern(Volumes, allocator, &kick_four, intro_bars - 2),
        try pattern(Volumes, allocator, &kick_verse, verse_bars),
        try pattern(Volumes, allocator, &kick_drive, verse_bars),
        try pattern(Volumes, allocator, &kick_verse, verse_bars),
        try pattern(Volumes, allocator, &kick_drive, climax_bars),
        try pattern(Volumes, allocator, &.{.{ .value = 1.0 }}, 1),
    });

    const snare_section = try (try pattern(Volumes, allocator, &snare_backbeat, verse_bars - 1)).concat(allocator, try pattern(Volumes, allocator, &snare_fill, 1));
    const snare = try join(Volumes, allocator, &.{
        try pattern(Volumes, allocator, &silent_bar, intro_bars - 1),
        try pattern(Volumes, allocator, &snare_fill, 1),
        snare_section,
        snare_section,
        snare_section,
        try pattern(Volumes, allocator, &snare_backbeat, climax_bars - 1),
        try pattern(Volumes, allocator, &snare_fill, 1),
        try pattern(Volumes, allocator, &.{.{ .value = 0.9 }}, 1),
    });

    const crash_section = try (try pattern(Volumes, allocator, &crash_first, 1)).concat(allocator, try pattern(Volumes, allocator, &silent_bar, verse_bars - 1));
    const crash = try join(Volumes, allocator, &.{
        try pattern(Volumes, allocator, &silent_bar, intro_bars),
        crash_section,
        crash_section,
        crash_section,
        try pattern(Volumes, allocator, &crash_first, climax_bars),
        try pattern(Volumes, allocator, &.{.{ .value = 1.0 }}, 1),
    });

    const hat_volume = try join(Volumes, allocator, &.{
        try pattern(Volumes, allocator, &silent_bar, 2),
        try pattern(Volumes, allocator, &hat_quarters, intro_bars - 2 + verse_bars),
        try pattern(Volumes, allocator, &hat_lift, verse_bars / 2),
        try pattern(Volumes, allocator, &hat_quarters, verse_bars),
        try pattern(Volumes, allocator, &hat_lift, climax_bars / 2),
        try pattern(Volumes, allocator, &.{.{ .value = 0.0 }}, 1),
    });
    const hat_stroke = try join(Strokes, allocator, &.{
        try pattern(Strokes, allocator, &closed_bar, intro_bars + verse_bars),
        try pattern(Strokes, allocator, &lift_strokes, verse_bars / 2),
        try pattern(Strokes, allocator, &closed_bar, verse_bars),
        try pattern(Strokes, allocator, &lift_strokes, climax_bars / 2),
        try pattern(Strokes, allocator, &.{.closed}, 1),
    });

    const bass_volume = try join(Volumes, allocator, &.{
        try pattern(Volumes, allocator, &silent_bar, 2),
        try pattern(Volumes, allocator, &chug, gallop_bars - 2),
        try pattern(Volumes, allocator, &.{.{ .value = 1.0 }}, 1),
    });

    const guitar_volume = try join(Volumes, allocator, &.{
        try pattern(Volumes, allocator, &chug, gallop_bars),
        try pattern(Volumes, allocator, &.{.{ .value = 1.0 }}, 1),
    });
    const guitar_mute = try join(Mutes, allocator, &.{
        try pattern(Mutes, allocator, &chug_mute, (gallop_bars - climax_bars) * configs.BEATS_PER_BAR),
        try pattern(Mutes, allocator, &climax_mute, climax_bars * configs.BEATS_PER_BAR),
        try pattern(Mutes, allocator, &.{.{ .amount = 0.0 }}, 1),
    });

    const guitar_root = try (try (try timeline.zip(guitar_volume)).zip(guitar_mute)).zip(roots);
    return .{
        .kick = try timeline.zip(kick),
        .snare = try timeline.zip(snare),
        .crash = try timeline.zip(crash),
        .hihat = try (try timeline.zip(hat_volume)).zip(hat_stroke),
        .bass = try (try timeline.zip(bass_volume)).zip(try roots.map(allocator, .pitch, Transpose{ .semitones = -12 })),
        .guitar_root = guitar_root,
        // A power chord: the second string plays the root's score a fifth up.
        .guitar_fifth = try guitar_root.map(allocator, .pitch, Transpose{ .semitones = 7 }),
    };
}

test "every vibrating body plays on the same timeline of 34 bars" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const scores = try compose(arena.allocator());

    const notes = gallop_bars * configs.BEATS_PER_BAR * 3 + 1;
    const beats: f64 = 34 * configs.BEATS_PER_BAR;
    inline for (@typeInfo(Scores).@"struct".fields) |field| {
        const layer = @field(scores, field.name);
        try std.testing.expectEqual(@as(usize, notes), layer.count());
        try std.testing.expectEqual(beats, layer.extent);
    }
}

test "the lift is the verse a fourth up, and the fifth string a fifth above the root" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const scores = try compose(arena.allocator());

    const verse_start = intro_bars * 12;
    const lift_start = (intro_bars + verse_bars) * 12;
    for (0..verse_bars * 12) |i| {
        const from = scores.guitar_root.columns.pitch[verse_start + i].name.midi();
        const to = scores.guitar_root.columns.pitch[lift_start + i].name.midi();
        try std.testing.expectEqual(from + 5, to);
    }
    for (scores.guitar_root.columns.pitch, scores.guitar_fifth.columns.pitch) |root, fifth| {
        try std.testing.expectEqual(root.name.midi() + 7, fifth.name.midi());
    }
}

test {
    std.testing.refAllDecls(@This());
}
