//! gallop: about one minute of rock built on one gallop rhythm (an eighth and two sixteenths).
//!
//! This is the user's side of the roles, and the root of the only module that imports `lightmix`
//! and the modules. The primitives are in `primitives.zig`, the scores in `scores.zig` and the
//! instrument set in `instruments.zig`; this file connects the modules and wraps the final array
//! in `lightmix.Wave`:
//!
//!     scores, one per vibrating body       write, compose, resolve       score
//!     resolved notes -> start and length   how long a note sounds        instrument set
//!     actual length, fade position         decide                        body
//!     waveform                             timbre, fade of the timbre    timbre, run by perform
//!     one waveform                         apply the fade, place, mix    mix

const std = @import("std");
const lightmix = @import("lightmix");
const score = @import("score");
const mix = @import("mix");
const configs = @import("./configs.zig");
const scores = @import("./scores.zig");
const instruments = @import("./instruments.zig");

const T = configs.T;
const Hits = scores.Hits;
const HiHat = scores.HiHat;
const BassLine = scores.BassLine;
const GuitarLine = scores.GuitarLine;
const Procedure = instruments.Procedure;

/// Tempo, meter and sample rate every primitive resolves against.
const context: score.Context = .{
    .bpm = configs.BPM,
    .time_signature = .{ .numerator = configs.BEATS_PER_BAR, .denominator = configs.BEAT_VALUE },
    .sample_rate = configs.SAMPLE_RATE,
};

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

    try play(Hits, allocator, written.kick, instruments.kick_body, mixer.bus(.{ .gain = 0.75 }));
    try play(Hits, allocator, written.snare, instruments.snare_body, mixer.bus(.{ .gain = 0.55, .pan = 0.05 }));
    try play(Hits, allocator, written.crash, instruments.crash_body, mixer.bus(.{ .gain = 0.3, .pan = -0.45 }));
    try play(HiHat, allocator, written.hihat, instruments.hihat_body, mixer.bus(.{ .gain = 0.3, .pan = 0.35 }));
    try play(BassLine, allocator, written.bass, instruments.bass_body, mixer.bus(.{ .gain = 0.42 }));
    try play(GuitarLine, allocator, written.guitar_root, instruments.left_string, mixer.bus(.{ .gain = 0.42, .pan = -0.85 }));
    try play(GuitarLine, allocator, written.guitar_fifth, instruments.left_string, mixer.bus(.{ .gain = 0.3, .pan = -0.85 }));
    try play(GuitarLine, allocator, written.guitar_root, instruments.right_string, mixer.bus(.{ .gain = 0.42, .pan = 0.85 }));
    try play(GuitarLine, allocator, written.guitar_fifth, instruments.right_string, mixer.bus(.{ .gain = 0.3, .pan = 0.85 }));

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
