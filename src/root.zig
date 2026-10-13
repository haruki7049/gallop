//! gallop: about one minute of rock built on one gallop rhythm (an eighth and two sixteenths).
//!
//! This is the user's side of the roles, and the root of the only module that imports `lightmix`
//! and the modules. The primitives are in `primitives.zig` and the scores in `scores.zig`; this
//! file writes the instrument set, connects the modules, and wraps the final array in
//! `lightmix.Wave`:
//!
//!     scores, one per vibrating body       write, compose, resolve       score
//!     resolved notes -> start and length   how long a note sounds        instrument set (here)
//!     actual length, fade position         decide                        body
//!     waveform                             timbre, fade of the timbre    timbre, run by perform
//!     one waveform                         apply the fade, place, mix    mix

const std = @import("std");
const lightmix = @import("lightmix");
const score = @import("score");
const body = @import("body");
const perform = @import("perform");
const mix = @import("mix");
const timbre = @import("timbre");
const configs = @import("./configs.zig");
const scores = @import("./scores.zig");

const T = configs.T;
const Hits = scores.Hits;
const HiHat = scores.HiHat;
const BassLine = scores.BassLine;
const GuitarLine = scores.GuitarLine;

/// Tempo, meter and sample rate every primitive resolves against.
const context: score.Context = .{
    .bpm = configs.BPM,
    .time_signature = .{ .numerator = configs.BEATS_PER_BAR, .denominator = configs.BEAT_VALUE },
    .sample_rate = configs.SAMPLE_RATE,
};

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
    const written = try scores.compose(allocator);

    var mixer = try Mixer.init(allocator, configs.CHANNELS);
    defer mixer.deinit();

    try play(Hits, allocator, written.kick, kick_body, mixer.bus(.{ .gain = 0.75 }));
    try play(Hits, allocator, written.snare, snare_body, mixer.bus(.{ .gain = 0.55, .pan = 0.05 }));
    try play(Hits, allocator, written.crash, crash_body, mixer.bus(.{ .gain = 0.3, .pan = -0.45 }));
    try play(HiHat, allocator, written.hihat, hihat_body, mixer.bus(.{ .gain = 0.3, .pan = 0.35 }));
    try play(BassLine, allocator, written.bass, bass_body, mixer.bus(.{ .gain = 0.42 }));
    try play(GuitarLine, allocator, written.guitar_root, left_string, mixer.bus(.{ .gain = 0.42, .pan = -0.85 }));
    try play(GuitarLine, allocator, written.guitar_fifth, left_string, mixer.bus(.{ .gain = 0.3, .pan = -0.85 }));
    try play(GuitarLine, allocator, written.guitar_root, right_string, mixer.bus(.{ .gain = 0.42, .pan = 0.85 }));
    try play(GuitarLine, allocator, written.guitar_fifth, right_string, mixer.bus(.{ .gain = 0.3, .pan = 0.85 }));

    // The piece lasts as long as its timeline; a ringing crash may run past it.
    const end = try (score.Timing{ .beat = written.guitar_root.extent }).resolve(context);
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
