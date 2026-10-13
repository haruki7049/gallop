//! gallop: about one minute of rock built on one gallop rhythm (an eighth and two sixteenths).
//!
//! This is the user's side of the roles, and the root of the only module that imports `lightmix`
//! and the modules. It writes the primitives, the score of every vibrating body and the
//! instrument set, connects the modules, and wraps the final array in `lightmix.Wave`:
//!
//!     scores, one per vibrating body       write, compose, resolve       score
//!     resolved notes -> start and length   how long a note sounds        instrument set (here)
//!     actual length, fade position         decide                        body
//!     waveform                             timbre, fade of the timbre    timbre, run by perform
//!     one waveform                         apply the fade, place, mix    mix
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
const lightmix = @import("lightmix");
const pitch = @import("pitch");
const score = @import("score");
const body = @import("body");
const perform = @import("perform");
const mix = @import("mix");
const timbre = @import("timbre");
const configs = @import("./configs.zig");

const T = configs.T;

/// Tempo, meter and sample rate every primitive resolves against.
const context: score.Context = .{
    .bpm = configs.BPM,
    .time_signature = .{ .numerator = configs.BEATS_PER_BAR, .denominator = configs.BEAT_VALUE },
    .sample_rate = configs.SAMPLE_RATE,
};

// ---------------------------------------------------------------------------------------------
// Primitives. Timing and duration are the score module's defaults; these are the others.
// ---------------------------------------------------------------------------------------------

/// Twelve-tone equal temperament at A4 = 440 Hz.
const tuning: pitch.TwelveToneEqualTemperament = .{};

/// A pitch name, resolved to Hz with `tuning`. The name and the tuning stay apart in the pitch
/// module; this primitive puts the tuning in the type.
const Pitch = struct {
    name: pitch.TwelveTonePitch,

    pub const ResolveT = T;

    pub fn resolve(self: Pitch, ctx: score.Context) ResolveT {
        _ = ctx;
        return tuning.freq(self.name);
    }
};

/// The energy given to a vibrating body. Zero is a rest: the note does not sound.
const Volume = struct {
    value: T,

    pub const ResolveT = T;

    pub fn resolve(self: Volume, ctx: score.Context) ResolveT {
        _ = ctx;
        return self.value;
    }
};

/// How far the palm mutes a guitar string, from 0 (open) to 1 (fully muted).
const Mute = struct {
    amount: T,

    pub const ResolveT = T;

    pub fn resolve(self: Mute, ctx: score.Context) ResolveT {
        _ = ctx;
        return self.amount;
    }
};

/// How the hi-hat is struck. Closed and open are one vibrating body, so a closed hit chokes an
/// open one that is still ringing.
const Stroke = enum {
    closed,
    open,

    pub const ResolveT = Stroke;

    pub fn resolve(self: Stroke, ctx: score.Context) ResolveT {
        _ = ctx;
        return self;
    }
};

/// Moves a pitch by a number of semitones. A transformation of score information, written next
/// to the primitive it understands and applied with `Layer.map`.
const Transpose = struct {
    semitones: isize,

    pub fn apply(self: Transpose, from: Pitch) error{PitchOutOfRange}!Pitch {
        return .{ .name = try from.name.add(self.semitones) };
    }
};

// ---------------------------------------------------------------------------------------------
// The score.
// ---------------------------------------------------------------------------------------------

const Rhythm = score.Layer(.{ .timing = score.Timing, .duration = score.Duration });
const Volumes = score.Layer(.{ .volume = Volume });
const Mutes = score.Layer(.{ .mute = Mute });
const Strokes = score.Layer(.{ .stroke = Stroke });
const Pitches = score.Layer(.{ .pitch = Pitch });

/// Score of a drum: kick, snare or crash.
const Hits = score.Layer(.{ .timing = score.Timing, .duration = score.Duration, .volume = Volume });
/// Score of the hi-hat.
const HiHat = score.Layer(.{ .timing = score.Timing, .duration = score.Duration, .volume = Volume, .stroke = Stroke });
/// Score of the bass.
const BassLine = score.Layer(.{ .timing = score.Timing, .duration = score.Duration, .volume = Volume, .pitch = Pitch });
/// Score of one guitar string.
const GuitarLine = score.Layer(.{ .timing = score.Timing, .duration = score.Duration, .volume = Volume, .mute = Mute, .pitch = Pitch });

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
const Scores = struct {
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
fn compose(allocator: std.mem.Allocator) !Scores {
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

// ---------------------------------------------------------------------------------------------
// The instrument set: for every vibrating body, how long a note sounds if nothing cuts it, and
// which timbre sounds it. Which notes share a body is decided by which score is handed to it.
// ---------------------------------------------------------------------------------------------

/// The procedure for vibrating bodies whose resolved notes are `R`.
fn Procedure(comptime R: type) type {
    return perform.Procedure(T, R, body, .timing);
}

const Hit = Hits.Resolved;
const HiHatNote = HiHat.Resolved;
const BassNote = BassLine.Resolved;
const GuitarNote = GuitarLine.Resolved;

/// Seconds to frames.
fn toFrames(seconds: T) usize {
    return @intFromFloat(@round(seconds * @as(T, @floatFromInt(configs.SAMPLE_RATE))));
}

/// A generator for the noise of one note, seeded by the body and by where the note starts, so
/// the waveform of a note depends on nothing else.
fn seeded(salt: u64, start: usize) std.Random.DefaultPrng {
    return .init(salt ^ @as(u64, start));
}

/// A drum sounds for `seconds` unless its volume is zero.
fn drumLength(seconds: T, volume: T) usize {
    return if (volume > 0.0) toFrames(seconds) else 0;
}

const kick_timbre: timbre.Kick(T) = .{ .decay = 0.17 };
const snare_timbre: timbre.Snare(T) = .{};
const Cymbal = timbre.Cymbal(T);
const bass_timbre: timbre.Bass(T) = .{};
const left_guitar: timbre.Guitar(T) = .{ .detune = 6.0 };
const right_guitar: timbre.Guitar(T) = .{ .detune = 9.0, .drive = 10.0, .cabinet = 3900.0 };

fn kickLength(note: Hit) usize {
    return drumLength(0.55, note.volume);
}

fn kickTimbre(allocator: std.mem.Allocator, note: Hit, length: usize, frames: usize) anyerror![]T {
    return kick_timbre.render(allocator, configs.SAMPLE_RATE, note.volume, length, frames);
}

fn snareLength(note: Hit) usize {
    return drumLength(0.5, note.volume);
}

fn snareTimbre(allocator: std.mem.Allocator, note: Hit, length: usize, frames: usize) anyerror![]T {
    var prng = seeded(0x5a4e_0001, note.timing);
    return snare_timbre.render(allocator, prng.random(), configs.SAMPLE_RATE, note.volume, length, frames);
}

fn crashLength(note: Hit) usize {
    return drumLength(4.0, note.volume);
}

fn crashTimbre(allocator: std.mem.Allocator, note: Hit, length: usize, frames: usize) anyerror![]T {
    var prng = seeded(0xc4a5_0002, note.timing);
    return Cymbal.crash.render(allocator, prng.random(), configs.SAMPLE_RATE, note.volume, length, frames);
}

fn hihatLength(note: HiHatNote) usize {
    return switch (note.stroke) {
        .closed => drumLength(0.15, note.volume),
        .open => drumLength(1.0, note.volume),
    };
}

fn hihatTimbre(allocator: std.mem.Allocator, note: HiHatNote, length: usize, frames: usize) anyerror![]T {
    var prng = seeded(0x4a7_0003, note.timing);
    const cymbal = switch (note.stroke) {
        .closed => Cymbal.closed,
        .open => Cymbal.open,
    };
    return cymbal.render(allocator, prng.random(), configs.SAMPLE_RATE, note.volume, length, frames);
}

/// The bass holds each note almost to the next one.
fn bassLength(note: BassNote) usize {
    if (note.volume == 0.0) return 0;
    return note.duration - note.duration / 20;
}

fn bassTimbre(allocator: std.mem.Allocator, note: BassNote, length: usize, frames: usize) anyerror![]T {
    return bass_timbre.render(allocator, configs.SAMPLE_RATE, note.pitch, note.volume, length, frames);
}

/// A muted string is lifted early; an open one rings for its whole duration.
fn guitarLength(note: GuitarNote) usize {
    if (note.volume == 0.0) return 0;
    const held = 1.0 - 0.25 * note.mute;
    return @intFromFloat(@round(@as(T, @floatFromInt(note.duration)) * held));
}

fn leftGuitarTimbre(allocator: std.mem.Allocator, note: GuitarNote, length: usize, frames: usize) anyerror![]T {
    return left_guitar.render(allocator, configs.SAMPLE_RATE, note.pitch, note.mute, note.volume, length, frames);
}

fn rightGuitarTimbre(allocator: std.mem.Allocator, note: GuitarNote, length: usize, frames: usize) anyerror![]T {
    return right_guitar.render(allocator, configs.SAMPLE_RATE, note.pitch, note.mute, note.volume, length, frames);
}

const kick_body: Procedure(Hit).Body = .{ .length = kickLength, .timbre = kickTimbre };
const snare_body: Procedure(Hit).Body = .{ .length = snareLength, .timbre = snareTimbre };
const crash_body: Procedure(Hit).Body = .{ .length = crashLength, .timbre = crashTimbre };
/// The closed and the open hi-hat: one body.
const hihat_body: Procedure(HiHatNote).Body = .{ .length = hihatLength, .timbre = hihatTimbre };
const bass_body: Procedure(BassNote).Body = .{ .length = bassLength, .timbre = bassTimbre };
/// One string of the left guitar; the root and the fifth are two such bodies.
const left_string: Procedure(GuitarNote).Body = .{ .length = guitarLength, .timbre = leftGuitarTimbre };
/// One string of the right guitar.
const right_string: Procedure(GuitarNote).Body = .{ .length = guitarLength, .timbre = rightGuitarTimbre };

// ---------------------------------------------------------------------------------------------
// Connecting the modules.
// ---------------------------------------------------------------------------------------------

const Mixer = mix.Mixer(T);

/// Resolves the score of one vibrating body and runs the procedure on it into `bus`.
fn play(comptime L: type, allocator: std.mem.Allocator, layer: L, instrument: Procedure(L.Resolved).Body, bus: Mixer.Bus) !void {
    const notes = try layer.resolve(allocator, context);
    try Procedure(L.Resolved).run(allocator, instrument, notes, configs.SAMPLE_RATE, bus);
}

/// Renders the whole piece as interleaved stereo samples, normalized to `configs.PEAK`.
fn render(allocator: std.mem.Allocator) ![]T {
    const scores = try compose(allocator);

    var mixer = try Mixer.init(allocator, configs.CHANNELS);
    defer mixer.deinit();

    try play(Hits, allocator, scores.kick, kick_body, mixer.bus(.{ .gain = 0.75 }));
    try play(Hits, allocator, scores.snare, snare_body, mixer.bus(.{ .gain = 0.55, .pan = 0.05 }));
    try play(Hits, allocator, scores.crash, crash_body, mixer.bus(.{ .gain = 0.3, .pan = -0.45 }));
    try play(HiHat, allocator, scores.hihat, hihat_body, mixer.bus(.{ .gain = 0.3, .pan = 0.35 }));
    try play(BassLine, allocator, scores.bass, bass_body, mixer.bus(.{ .gain = 0.42 }));
    try play(GuitarLine, allocator, scores.guitar_root, left_string, mixer.bus(.{ .gain = 0.42, .pan = -0.85 }));
    try play(GuitarLine, allocator, scores.guitar_fifth, left_string, mixer.bus(.{ .gain = 0.3, .pan = -0.85 }));
    try play(GuitarLine, allocator, scores.guitar_root, right_string, mixer.bus(.{ .gain = 0.42, .pan = 0.85 }));
    try play(GuitarLine, allocator, scores.guitar_fifth, right_string, mixer.bus(.{ .gain = 0.3, .pan = 0.85 }));

    // The piece lasts as long as its timeline; a ringing crash may run past it.
    const end = try (score.Timing{ .beat = scores.guitar_root.extent }).resolve(context);
    const samples = try mixer.finish(end);
    mix.normalize(T, samples, configs.PEAK);
    return samples;
}

/// Entry point used by `lightmix.addWave` to generate `gallop.wav`.
pub fn gen(init: std.process.Init) !lightmix.Wave(T) {
    const allocator = init.arena.allocator();
    const samples = try render(allocator);
    return lightmix.Wave(T).init(samples, allocator, .{ .sample_rate = configs.SAMPLE_RATE, .channels = configs.CHANNELS });
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

test "the piece is about a minute long and normalized" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const samples = try render(arena.allocator());

    const seconds = @as(f64, @floatFromInt(samples.len / configs.CHANNELS)) / @as(f64, @floatFromInt(configs.SAMPLE_RATE));
    try std.testing.expect(seconds > 55.0 and seconds < 65.0);

    var peak: T = 0.0;
    for (samples) |s| peak = @max(peak, @abs(s));
    try std.testing.expectApproxEqAbs(configs.PEAK, peak, 1e-9);
}

test {
    std.testing.refAllDecls(@This());
}
