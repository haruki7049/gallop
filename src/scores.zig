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
//! Each section of the form is written as a function that gives the score of every vibrating
//! body for that section, and the sections are joined body by body. Within a section, every body
//! zips its primitives onto bars of the base gallop (or the final chord), so every body plays on
//! the same timeline: 128 gallops and the final chord. A zero volume is a rest.

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

/// When notes start and how long they are written to last.
const Rhythm = score.Layer(.{ .timing = score.Timing, .duration = score.Duration });
/// A list of volumes.
const Volumes = score.Layer(.{ .volume = Volume });
/// A list of palm mutings.
const Mutes = score.Layer(.{ .mute = Mute });
/// A list of hi-hat strokes.
const Strokes = score.Layer(.{ .stroke = Stroke });
/// A list of pitches.
const Pitches = score.Layer(.{ .pitch = Pitch });
/// A rhythm with a pitch on every note.
const Melody = score.Layer(.{ .timing = score.Timing, .duration = score.Duration, .pitch = Pitch });

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

/// Bars of the intro.
const intro_bars = 4;
/// Bars of a verse, and of the lift.
const verse_bars = 8;
/// Bars of the climax.
const climax_bars = 4;
/// Bars of gallops before the ending.
const gallop_bars = intro_bars + 3 * verse_bars + climax_bars;

/// E2: the root of the intro, of the first two bars of the riff, and of the final chord. Like
/// every root, a layer of one pitch that is not placed in time, so that zip copies it onto
/// every note of a rhythm.
const e2 = Pitches.notate(&.{.{ .name = .{ .code = .e, .octave = 2 } }});
/// C3: the root of the third bar of the riff.
const c3 = Pitches.notate(&.{.{ .name = .{ .code = .c, .octave = 3 } }});
/// D3: the root of the fourth bar of the riff.
const d3 = Pitches.notate(&.{.{ .name = .{ .code = .d, .octave = 3 } }});

/// One bar of volumes, written as four gallops of three notes each.
fn bar(comptime gallops: [4][3]T) [12]Volume {
    var out: [12]Volume = undefined;
    for (gallops, 0..) |notes, beat| {
        for (notes, 0..) |value, n| out[beat * 3 + n] = .{ .value = value };
    }
    return out;
}

/// A gallop that does not sound.
const off = [3]T{ 0.0, 0.0, 0.0 };
/// Only the eighth of the gallop.
const quarter = [3]T{ 0.9, 0.0, 0.0 };
/// The whole gallop.
const run = [3]T{ 1.0, 0.8, 0.9 };

/// A bar that does not sound.
const silent_bar = bar(.{ off, off, off, off });
/// Kick on every beat: the intro, before the verse.
const kick_four = bar(.{ quarter, quarter, quarter, quarter });
/// Kick on the whole gallop of beats 0 and 2: the verse.
const kick_verse = bar(.{ run, off, run, off });
/// Kick on the whole gallop of every beat: the lift and the climax.
const kick_drive = bar(.{ run, run, run, run });
/// Snare on beats 1 and 3.
const snare_backbeat = bar(.{ off, quarter, off, quarter });
/// The last bar of a section: snare on beat 1, then whole gallops growing louder on beats 2 and 3.
const snare_fill = bar(.{ off, quarter, .{ 0.7, 0.6, 0.75 }, .{ 0.85, 0.9, 1.0 } });
/// Crash on the first note of the bar: the first bar of a section, and every bar of the climax.
const crash_first = bar(.{ .{ 1.0, 0.0, 0.0 }, off, off, off });
/// Hi-hat on every beat, with beats 0 and 2 a little louder: the intro and the verse.
const hat_quarters = bar(.{ .{ 0.7, 0.0, 0.0 }, .{ 0.6, 0.0, 0.0 }, .{ 0.7, 0.0, 0.0 }, .{ 0.6, 0.0, 0.0 } });
/// Hi-hat on the whole gallop of every beat.
const hat_gallop = bar(.{ .{ 0.75, 0.45, 0.55 }, .{ 0.7, 0.45, 0.55 }, .{ 0.75, 0.45, 0.55 }, .{ 0.7, 0.45, 0.55 } });
/// Two bars of the lift: the second ends on an open hi-hat that rings into the next downbeat.
const hat_lift = hat_gallop ++ bar(.{ .{ 0.75, 0.45, 0.55 }, .{ 0.7, 0.45, 0.55 }, .{ 0.75, 0.45, 0.55 }, .{ 0.8, 0.0, 0.0 } });
/// A bar of closed strokes.
const closed_bar = [_]Stroke{.closed} ** 12;
/// Strokes of `hat_lift`: closed, except the open hi-hat on beat 3 of the second bar.
const lift_strokes = closed_bar ++ [_]Stroke{.closed} ** 9 ++ [_]Stroke{ .open, .closed, .closed };
/// Bass and guitar volumes of one bar: the eighth of each gallop louder than its sixteenths.
const chug = bar(.{ .{ 1.0, 0.7, 0.8 }, .{ 0.9, 0.7, 0.8 }, .{ 0.95, 0.7, 0.8 }, .{ 0.9, 0.7, 0.8 } });
/// Palm muting of one gallop: the eighth a little open, the sixteenths tight.
const chug_mute = [_]Mute{ .{ .amount = 0.55 }, .{ .amount = 0.9 }, .{ .amount = 0.9 } };
/// Palm muting of one gallop in the climax: more open than `chug_mute`.
const climax_mute = [_]Mute{ .{ .amount = 0.3 }, .{ .amount = 0.7 }, .{ .amount = 0.7 } };

/// The scores of every vibrating body.
pub const Scores = struct {
    /// The kick drum.
    kick: Hits,
    /// The snare drum.
    snare: Hits,
    /// The crash cymbal.
    crash: Hits,
    /// The hi-hat, closed and open.
    hihat: HiHat,
    /// The bass: the roots an octave below the root string.
    bass: BassLine,
    /// The root string of each guitar.
    guitar_root: GuitarLine,
    /// The fifth string of each guitar: the root string's score a fifth up.
    guitar_fifth: GuitarLine,
};

/// One section of the form: the score of every vibrating body but the fifth string, which is
/// derived from the root string once the sections are joined.
const Section = struct {
    /// The kick drum.
    kick: Hits,
    /// The snare drum.
    snare: Hits,
    /// The crash cymbal.
    crash: Hits,
    /// The hi-hat, closed and open.
    hihat: HiHat,
    /// The bass.
    bass: BassLine,
    /// The root string of each guitar.
    guitar_root: GuitarLine,
};

/// Concatenates `sections` in order, body by body.
fn join(comptime S: type, allocator: std.mem.Allocator, sections: []const S) !S {
    var result: S = undefined;

    inline for (@typeInfo(S).@"struct".fields) |field| {
        const parts = try allocator.alloc(field.type, sections.len);
        for (sections, parts) |section, *part| part.* = @field(section, field.name);
        @field(result, field.name) = try field.type.join(allocator, parts);
    }

    return result;
}

/// The riff on four bars of `measure`: E E C D, one root per bar.
fn riff(allocator: std.mem.Allocator, measure: Rhythm) !Melody {
    return Melody.join(allocator, &.{
        try measure.zip(allocator, e2),
        try measure.zip(allocator, e2),
        try measure.zip(allocator, c3),
        try measure.zip(allocator, d3),
    });
}

/// The snare of a section of `bars` bars: the backbeat, and a fill in the last bar.
fn backbeat(allocator: std.mem.Allocator, bars: usize) !Volumes {
    return Volumes.join(allocator, &.{
        try Volumes.notate(&snare_backbeat).repeat(allocator, bars - 1),
        Volumes.notate(&snare_fill),
    });
}

/// The crash of a section of `bars` bars: on the first note of the first bar only.
fn opening(allocator: std.mem.Allocator, bars: usize) !Volumes {
    return Volumes.join(allocator, &.{
        Volumes.notate(&crash_first),
        try Volumes.notate(&silent_bar).repeat(allocator, bars - 1),
    });
}

/// The bass of a section: `melody` an octave down, at `volume`.
fn bassline(allocator: std.mem.Allocator, melody: Melody, volume: Volumes) !BassLine {
    return (try melody.map(allocator, .pitch, Transpose{ .semitones = -12 })).zip(allocator, volume);
}

/// The root string of a section of `bars` bars: `melody` chugging, every gallop palm-muted as
/// `mute`.
fn chugging(allocator: std.mem.Allocator, melody: Melody, bars: usize, mute: []const Mute) !GuitarLine {
    const volume = try Volumes.notate(&chug).repeat(allocator, bars);
    const mutes = try Mutes.notate(mute).repeat(allocator, bars * configs.BEATS_PER_BAR);

    return (try melody.zip(allocator, volume)).zip(allocator, mutes);
}

/// The intro: guitars on E; the bass, the kick and the hi-hat join after two bars.
fn intro(allocator: std.mem.Allocator, measure: Rhythm) !Section {
    const bars = intro_bars;
    // Bars the guitars play alone.
    const alone = 2;

    const rhythm = try measure.repeat(allocator, bars);

    const melody = try rhythm.zip(allocator, e2);

    return .{
        .kick = try rhythm.zip(allocator, try Volumes.join(allocator, &.{
            try Volumes.notate(&silent_bar).repeat(allocator, alone),
            try Volumes.notate(&kick_four).repeat(allocator, bars - alone),
        })),
        .snare = try rhythm.zip(allocator, try Volumes.join(allocator, &.{
            try Volumes.notate(&silent_bar).repeat(allocator, bars - 1),
            Volumes.notate(&snare_fill),
        })),
        .crash = try rhythm.zip(allocator, try Volumes.notate(&silent_bar).repeat(allocator, bars)),
        .hihat = try (try rhythm.zip(allocator, try Volumes.join(allocator, &.{
            try Volumes.notate(&silent_bar).repeat(allocator, alone),
            try Volumes.notate(&hat_quarters).repeat(allocator, bars - alone),
        }))).zip(allocator, try Strokes.notate(&closed_bar).repeat(allocator, bars)),

        .bass = try bassline(allocator, melody, try Volumes.join(allocator, &.{
            try Volumes.notate(&silent_bar).repeat(allocator, alone),
            try Volumes.notate(&chug).repeat(allocator, bars - alone),
        })),
        .guitar_root = try chugging(allocator, melody, bars, &chug_mute),
    };
}

/// A verse: the riff twice, the kick on beats 0 and 2.
fn verse(allocator: std.mem.Allocator, measure: Rhythm) !Section {
    const bars = verse_bars;

    const rhythm = try measure.repeat(allocator, bars);

    const theme = try riff(allocator, measure);
    const melody = try theme.concat(allocator, theme);

    return .{
        .kick = try rhythm.zip(allocator, try Volumes.notate(&kick_verse).repeat(allocator, bars)),
        .snare = try rhythm.zip(allocator, try backbeat(allocator, bars)),
        .crash = try rhythm.zip(allocator, try opening(allocator, bars)),
        .hihat = try (try rhythm.zip(allocator, try Volumes.notate(&hat_quarters).repeat(allocator, bars))).zip(allocator, try Strokes.notate(&closed_bar).repeat(allocator, bars)),

        .bass = try bassline(allocator, melody, try Volumes.notate(&chug).repeat(allocator, bars)),
        .guitar_root = try chugging(allocator, melody, bars, &chug_mute),
    };
}

/// The lift: the verse transposed up a fourth, the kick on every gallop, an open hi-hat every
/// two bars.
fn lift(allocator: std.mem.Allocator, measure: Rhythm) !Section {
    const bars = verse_bars;

    const rhythm = try measure.repeat(allocator, bars);

    const theme = try riff(allocator, measure);
    const melody = try (try theme.concat(allocator, theme)).map(allocator, .pitch, Transpose{ .semitones = 5 });

    return .{
        .kick = try rhythm.zip(allocator, try Volumes.notate(&kick_drive).repeat(allocator, bars)),
        .snare = try rhythm.zip(allocator, try backbeat(allocator, bars)),
        .crash = try rhythm.zip(allocator, try opening(allocator, bars)),
        .hihat = try (try rhythm.zip(allocator, try Volumes.notate(&hat_lift).repeat(allocator, bars / 2))).zip(allocator, try Strokes.notate(&lift_strokes).repeat(allocator, bars / 2)),

        .bass = try bassline(allocator, melody, try Volumes.notate(&chug).repeat(allocator, bars)),
        .guitar_root = try chugging(allocator, melody, bars, &chug_mute),
    };
}

/// The climax: the riff transposed up a fifth, a crash on every bar, the guitars less muted.
fn climax(allocator: std.mem.Allocator, measure: Rhythm) !Section {
    const bars = climax_bars;

    const rhythm = try measure.repeat(allocator, bars);

    const melody = try (try riff(allocator, measure)).map(allocator, .pitch, Transpose{ .semitones = 7 });

    return .{
        .kick = try rhythm.zip(allocator, try Volumes.notate(&kick_drive).repeat(allocator, bars)),
        .snare = try rhythm.zip(allocator, try backbeat(allocator, bars)),
        .crash = try rhythm.zip(allocator, try Volumes.notate(&crash_first).repeat(allocator, bars)),
        .hihat = try (try rhythm.zip(allocator, try Volumes.notate(&hat_lift).repeat(allocator, bars / 2))).zip(allocator, try Strokes.notate(&lift_strokes).repeat(allocator, bars / 2)),

        .bass = try bassline(allocator, melody, try Volumes.notate(&chug).repeat(allocator, bars)),
        .guitar_root = try chugging(allocator, melody, bars, &climax_mute),
    };
}

/// The ending: one open chord on E with the kick, the snare and the crash.
fn finale(allocator: std.mem.Allocator) !Section {
    const melody = try ending.zip(allocator, e2);

    return .{
        .kick = try ending.zip(allocator, Volumes.notate(&.{.{ .value = 1.0 }})),
        .snare = try ending.zip(allocator, Volumes.notate(&.{.{ .value = 0.9 }})),
        .crash = try ending.zip(allocator, Volumes.notate(&.{.{ .value = 1.0 }})),
        .hihat = try (try ending.zip(allocator, Volumes.notate(&.{.{ .value = 0.0 }}))).zip(allocator, Strokes.notate(&.{.closed})),

        .bass = try bassline(allocator, melody, Volumes.notate(&.{.{ .value = 1.0 }})),
        .guitar_root = try (try melody.zip(allocator, Volumes.notate(&.{.{ .value = 1.0 }}))).zip(allocator, Mutes.notate(&.{.{ .amount = 0.0 }})),
    };
}

/// Writes the score of every vibrating body with an arena-like `allocator`: nothing is freed
/// until the whole score is.
pub fn compose(allocator: std.mem.Allocator) !Scores {
    // Every section but the ending is written on bars of the base gallop.
    const measure = try gallop.repeat(allocator, configs.BEATS_PER_BAR);

    const piece = try join(Section, allocator, &.{
        try intro(allocator, measure),
        try verse(allocator, measure),
        try lift(allocator, measure),
        try verse(allocator, measure),
        try climax(allocator, measure),
        try finale(allocator),
    });

    return .{
        .kick = piece.kick,
        .snare = piece.snare,
        .crash = piece.crash,
        .hihat = piece.hihat,
        .bass = piece.bass,
        .guitar_root = piece.guitar_root,

        // A power chord: the second string plays the root's score a fifth up.
        .guitar_fifth = try piece.guitar_root.map(allocator, .pitch, Transpose{ .semitones = 7 }),
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
        // Every section writes each body on its own copy of the bars; they must still agree.
        try std.testing.expectEqualSlices(f64, scores.kick.origins, layer.origins);
        try std.testing.expectEqualDeep(scores.kick.columns.timing, layer.columns.timing);
        try std.testing.expectEqualDeep(scores.kick.columns.duration, layer.columns.duration);
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
