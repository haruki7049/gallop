//! The instrument set: for every vibrating body, how long a note sounds if nothing cuts it, and
//! which timbre sounds it. Which notes share a body is decided by which score is handed to it.

const std = @import("std");
const body = @import("body");
const perform = @import("perform");
const timbre = @import("timbre");
const configs = @import("./configs.zig");
const scores = @import("./scores.zig");

const T = configs.T;
const Hits = scores.Hits;
const HiHat = scores.HiHat;
const BassLine = scores.BassLine;
const GuitarLine = scores.GuitarLine;

/// The procedure for vibrating bodies whose resolved notes are `R`.
pub fn Procedure(comptime R: type) type {
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

pub const kick_body: Procedure(Hit).Body = .{ .length = kickLength, .timbre = kickTimbre };
pub const snare_body: Procedure(Hit).Body = .{ .length = snareLength, .timbre = snareTimbre };
pub const crash_body: Procedure(Hit).Body = .{ .length = crashLength, .timbre = crashTimbre };
/// The closed and the open hi-hat: one body.
pub const hihat_body: Procedure(HiHatNote).Body = .{ .length = hihatLength, .timbre = hihatTimbre };
pub const bass_body: Procedure(BassNote).Body = .{ .length = bassLength, .timbre = bassTimbre };
/// One string of the left guitar; the root and the fifth are two such bodies.
pub const left_string: Procedure(GuitarNote).Body = .{ .length = guitarLength, .timbre = leftGuitarTimbre };
/// One string of the right guitar.
pub const right_string: Procedure(GuitarNote).Body = .{ .length = guitarLength, .timbre = rightGuitarTimbre };

test {
    std.testing.refAllDecls(@This());
}
