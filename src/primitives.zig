//! The primitives of this piece, and the transformations written next to them.
//!
//! Timing and duration are the score module's defaults; these are the others. Each primitive has
//! `ResolveT` and `resolve(self, ctx: score.Context)`.

const pitch = @import("pitch");
const score = @import("score");
const configs = @import("./configs.zig");

const T = configs.T;

/// Twelve-tone equal temperament at A4 = 440 Hz.
pub const tuning: pitch.TwelveToneEqualTemperament = .{};

/// A pitch name, resolved to Hz with `tuning`. The name and the tuning stay apart in the pitch
/// module; this primitive puts the tuning in the type.
pub const Pitch = struct {
    /// Pitch class and octave, such as E2.
    name: pitch.TwelveTonePitch,

    /// A frequency in Hz.
    pub const ResolveT = T;

    /// Resolves the name to its frequency in `tuning`. Ignores `ctx`.
    pub fn resolve(self: Pitch, ctx: score.Context) ResolveT {
        _ = ctx;
        return tuning.freq(self.name);
    }
};

/// The energy given to a vibrating body. Zero is a rest: the note does not sound.
pub const Volume = struct {
    /// Linear level from 0 (a rest) to 1 (full).
    value: T,

    /// A linear level, handed to the timbre as its volume.
    pub const ResolveT = T;

    /// Resolves to `value` as it is. Ignores `ctx`.
    pub fn resolve(self: Volume, ctx: score.Context) ResolveT {
        _ = ctx;
        return self.value;
    }
};

/// How far the palm mutes a guitar string, from 0 (open) to 1 (fully muted).
pub const Mute = struct {
    /// From 0 (open) to 1 (fully muted).
    amount: T,

    /// The amount of muting, handed to the guitar timbre and to the length of the note.
    pub const ResolveT = T;

    /// Resolves to `amount` as it is. Ignores `ctx`.
    pub fn resolve(self: Mute, ctx: score.Context) ResolveT {
        _ = ctx;
        return self.amount;
    }
};

/// How the hi-hat is struck. Closed and open are one vibrating body, so a closed hit chokes an
/// open one that is still ringing.
pub const Stroke = enum {
    /// Struck with the pedal down: short.
    closed,
    /// Struck with the pedal up: rings, unless the next hit cuts it.
    open,

    /// The stroke itself; the instrument set picks the cymbal setting and the length from it.
    pub const ResolveT = Stroke;

    /// Resolves to the stroke as it is. Ignores `ctx`.
    pub fn resolve(self: Stroke, ctx: score.Context) ResolveT {
        _ = ctx;
        return self;
    }
};

/// Moves a pitch by a number of semitones. A transformation of score information, written next
/// to the primitive it understands and applied with `Layer.map`.
pub const Transpose = struct {
    /// Semitones to move by; negative goes down.
    semitones: isize,

    /// Returns `from` moved by `semitones`, or `error.PitchOutOfRange` when the result falls
    /// outside the range of `pitch.TwelveTonePitch`.
    pub fn apply(self: Transpose, from: Pitch) error{PitchOutOfRange}!Pitch {
        return .{ .name = try from.name.add(self.semitones) };
    }
};
