//! Layers of score information: named primitives, zip, concatenation and resolution.
//!
//! A primitive is any type with exactly two declarations, `ResolveT` and
//! `resolve(self, ctx: Context) ResolveT` (or an error union of `ResolveT`). `Layer` builds a layer
//! type from named primitives at compile time; zip, concatenation and resolution are written once,
//! here, and never read the data of a primitive.
//!
//! A layer also carries where it sits in time: its `extent` in beats, and the `origins` of its
//! elements. Concatenation places the second layer `extent` beats after the first one by adding to
//! the origins of its elements, and `resolve` hands each element its origin through
//! `Context.origin`. A primitive that places itself in time adds the origin; the others ignore it.
//!
//! Memory: zip borrows the slices of both layers, and allocates only to broadcast a layer of one
//! element. Concatenation, `repeat`, `map` and `resolve` allocate new slices with the allocator they
//! are given and never free their inputs, so a score is meant to be built with an arena and freed
//! at once.

const std = @import("std");
const Context = @import("./context.zig");

/// Errors `zip` returns.
pub const ZipError = error{
    /// The layers have different numbers of elements. Make them equal by concatenation first.
    MismatchedCount,
    /// Both layers are placed in time, and their extents or origins differ.
    MismatchedExtent,
};

/// Returns the layer type made of the given named primitives, for example
/// `Layer(.{ .timing = Timing, .pitch = Pitch })`. Each combination of primitives is its own type,
/// and the order the primitives are written in does not matter.
pub fn inner(comptime spec: anytype) type {
    const fields = @typeInfo(@TypeOf(spec)).@"struct".fields;
    var names: [fields.len][]const u8 = undefined;
    var types: [fields.len]type = undefined;
    for (fields, 0..) |field, i| {
        names[i] = field.name;
        types[i] = @field(spec, field.name);
    }
    return Sorted(fields.len, names, types);
}

/// Rejects, at compile time, a type that does not keep the primitive contract.
fn assertPrimitive(comptime P: type) void {
    if (!@hasDecl(P, "ResolveT")) @compileError(@typeName(P) ++ " is not a primitive: it has no `ResolveT`");
    if (!@hasDecl(P, "resolve")) @compileError(@typeName(P) ++ " is not a primitive: it has no `resolve`");

    const info = @typeInfo(@TypeOf(P.resolve)).@"fn";
    if (info.params.len != 2 or info.params[1].type == null or info.params[1].type.? != Context)
        @compileError(@typeName(P) ++ ".resolve must take `self` and a `Context`");

    const R = info.return_type.?;
    const payload = switch (@typeInfo(R)) {
        .error_union => |error_union| error_union.payload,
        else => R,
    };
    if (payload != P.ResolveT) @compileError(@typeName(P) ++ ".resolve must return `ResolveT` or an error union of it");
}

/// Builds a struct type from field names and field types.
fn StructOf(comptime n: usize, comptime names: [n][]const u8, comptime types: [n]type) type {
    return @Struct(.auto, null, &names, &types, &@splat(.{}));
}

/// Sorts the primitives by name, so that the same primitives in another order give the same type.
fn Sorted(comptime n: usize, comptime names: [n][]const u8, comptime types: [n]type) type {
    if (n == 0) @compileError("a layer needs at least one primitive");

    var order: [n]usize = undefined;
    for (&order, 0..) |*index, i| index.* = i;
    std.mem.sort(usize, &order, names, struct {
        fn lessThan(all: [n][]const u8, a: usize, b: usize) bool {
            return std.mem.lessThan(u8, all[a], all[b]);
        }
    }.lessThan);

    var sorted_names: [n][]const u8 = undefined;
    var sorted_types: [n]type = undefined;
    for (order, 0..) |from, to| {
        assertPrimitive(types[from]);
        sorted_names[to] = names[from];
        sorted_types[to] = types[from];
    }
    return LayerOf(StructOf(n, sorted_names, sorted_types));
}

/// The origin of element `i`; an empty `origins` means zero for every element.
fn originAt(origins: []const f64, i: usize) f64 {
    return if (origins.len == 0) 0.0 else origins[i];
}

/// The layer type of an element type `E`: a struct with one field per primitive.
fn LayerOf(comptime E: type) type {
    const fields = @typeInfo(E).@"struct".fields;

    return struct {
        const Self = @This();

        /// One element: one value per primitive.
        pub const Item = E;
        /// One slice per primitive.
        pub const Columns = blk: {
            var names: [fields.len][]const u8 = undefined;
            var types: [fields.len]type = undefined;
            for (fields, 0..) |field, i| {
                names[i] = field.name;
                types[i] = []const field.type;
            }
            break :blk StructOf(fields.len, names, types);
        };
        /// One resolved value per primitive, under the same names.
        pub const Resolved = blk: {
            var names: [fields.len][]const u8 = undefined;
            var types: [fields.len]type = undefined;
            for (fields, 0..) |field, i| {
                names[i] = field.name;
                types[i] = field.type.ResolveT;
            }
            break :blk StructOf(fields.len, names, types);
        };
        /// Names a primitive of this layer, for `map`.
        pub const Name = std.meta.FieldEnum(E);

        /// One slice per primitive, all with the same number of elements.
        columns: Columns,
        /// Length of this layer in beats: a layer concatenated after this one starts this many
        /// beats later. Zero for a layer that is not placed in time, such as a list of pitches.
        extent: f64 = 0.0,
        /// Beats from the start of this layer to the start of the segment each element was written
        /// in, one per element. Set by concatenation; empty means zero for every element.
        origins: []const f64 = &.{},

        /// A layer with no elements that lasts `extent` beats: silence to concatenate.
        pub fn empty(extent: f64) Self {
            var result: Self = .{ .columns = undefined, .extent = extent };
            inline for (fields) |field| @field(result.columns, field.name) = &.{};
            return result;
        }

        /// Number of elements.
        pub fn count(self: Self) usize {
            return @field(self.columns, fields[0].name).len;
        }

        /// Whether this layer is placed in time.
        fn placed(self: Self) bool {
            return self.extent != 0.0 or self.origins.len != 0;
        }

        /// The layer type that zipping with `L` gives. A name used on both sides is a compile error.
        fn Zipped(comptime L: type) type {
            const all = fields ++ @typeInfo(L.Item).@"struct".fields;
            var names: [all.len][]const u8 = undefined;
            var types: [all.len]type = undefined;
            for (all, 0..) |field, i| {
                if (i >= fields.len and @hasField(E, field.name))
                    @compileError("cannot zip: both layers have a primitive named `" ++ field.name ++ "`");
                names[i] = field.name;
                types[i] = field.type;
            }
            return Sorted(all.len, names, types);
        }

        /// Whether this layer is one element not placed in time, which `zip` broadcasts.
        fn scalar(self: Self) bool {
            return self.count() == 1 and !self.placed();
        }

        /// This layer's one element copied `n` times, in a layer not placed in time. Copies the
        /// element without reading it. The caller owns the returned slices.
        fn broadcast(self: Self, allocator: std.mem.Allocator, n: usize) std.mem.Allocator.Error!Self {
            var result: Self = .{ .columns = undefined };
            inline for (fields) |field| {
                const column = try allocator.alloc(field.type, n);
                @memset(column, @field(self.columns, field.name)[0]);
                @field(result.columns, field.name) = column;
            }
            return result;
        }

        /// Pairs this layer with another one, element by element.
        ///
        /// Returns `error.MismatchedCount` when the numbers of elements differ, never truncating or
        /// repeating, with one exception: a layer of one element that is not placed in time is
        /// broadcast, its element copied onto every element of the other layer, on either side.
        /// When only one layer is placed in time, the result takes its extent and origins; when
        /// both are, they must agree, or `error.MismatchedExtent` is returned.
        ///
        /// Memory: borrows the slices of both layers. Only a broadcast allocates, with `allocator`,
        /// the copies of the broadcast element; the caller owns them.
        pub fn zip(self: Self, allocator: std.mem.Allocator, other: anytype) (ZipError || std.mem.Allocator.Error)!Zipped(@TypeOf(other)) {
            if (self.count() != other.count()) {
                if (self.scalar()) return (try self.broadcast(allocator, other.count())).zip(allocator, other);
                if (other.scalar()) return self.zip(allocator, try other.broadcast(allocator, self.count()));
                return error.MismatchedCount;
            }

            var result: Zipped(@TypeOf(other)) = .{ .columns = undefined };
            inline for (fields) |field| @field(result.columns, field.name) = @field(self.columns, field.name);
            inline for (@typeInfo(@TypeOf(other).Item).@"struct".fields) |field| {
                @field(result.columns, field.name) = @field(other.columns, field.name);
            }

            if (!other.placed()) {
                result.extent = self.extent;
                result.origins = self.origins;
            } else if (!self.placed()) {
                result.extent = other.extent;
                result.origins = other.origins;
            } else {
                if (self.extent != other.extent) return error.MismatchedExtent;
                for (0..self.count()) |i| {
                    if (originAt(self.origins, i) != originAt(other.origins, i)) return error.MismatchedExtent;
                }
                result.extent = self.extent;
                result.origins = if (self.origins.len != 0) self.origins else other.origins;
            }
            return result;
        }

        /// Places `other` after this layer: its elements follow these ones, and it starts `extent`
        /// beats after this layer starts. The result lasts both extents. The caller owns the
        /// returned slices.
        pub fn concat(self: Self, allocator: std.mem.Allocator, other: Self) std.mem.Allocator.Error!Self {
            var result: Self = .{ .columns = undefined, .extent = self.extent + other.extent };
            inline for (fields) |field| {
                @field(result.columns, field.name) = try std.mem.concat(allocator, field.type, &.{
                    @field(self.columns, field.name),
                    @field(other.columns, field.name),
                });
            }

            if (self.origins.len == 0 and other.origins.len == 0 and self.extent == 0.0) return result;

            const origins = try allocator.alloc(f64, self.count() + other.count());
            for (0..self.count()) |i| origins[i] = originAt(self.origins, i);
            for (0..other.count()) |i| origins[self.count() + i] = self.extent + originAt(other.origins, i);
            result.origins = origins;
            return result;
        }

        /// Concatenates this layer with itself until it appears `times` times. Zero times gives an
        /// empty layer that lasts no time. The caller owns the returned slices.
        pub fn repeat(self: Self, allocator: std.mem.Allocator, times: usize) std.mem.Allocator.Error!Self {
            var result = empty(0.0);
            for (0..times) |_| result = try result.concat(allocator, self);
            return result;
        }

        /// Returns this layer with every element of the primitive `name` replaced by
        /// `transform.apply(element)`. `apply` returns the same primitive type, or an error union
        /// of it. Shifting, transposing and other transformations of score information are written
        /// as such a `transform`, next to the primitive they understand. The caller owns the
        /// returned slice.
        pub fn map(self: Self, allocator: std.mem.Allocator, comptime name: Name, transform: anytype) !Self {
            const P = @FieldType(E, @tagName(name));
            const column = @field(self.columns, @tagName(name));

            const out = try allocator.alloc(P, column.len);
            errdefer allocator.free(out);
            for (column, out) |element, *mapped| {
                const value = transform.apply(element);
                mapped.* = if (@typeInfo(@TypeOf(value)) == .error_union) try value else value;
            }

            var result = self;
            @field(result.columns, @tagName(name)) = out;
            return result;
        }

        /// Resolves every element by calling each primitive's `resolve` with `ctx`, whose origin
        /// is moved to the origin of the element. Returns the first error a primitive returns. The
        /// caller owns the returned slice.
        pub fn resolve(self: Self, allocator: std.mem.Allocator, ctx: Context) ![]Resolved {
            const out = try allocator.alloc(Resolved, self.count());
            errdefer allocator.free(out);
            for (out, 0..) |*item, n| {
                var element_ctx = ctx;
                element_ctx.origin = ctx.origin + originAt(self.origins, n);
                inline for (fields) |field| {
                    const value = @field(self.columns, field.name)[n].resolve(element_ctx);
                    @field(item, field.name) = if (@typeInfo(@TypeOf(value)) == .error_union) try value else value;
                }
            }
            return out;
        }
    };
}

// Primitives used by the tests below. They are written the way a user of this module writes one.

const Timing = @import("./timing.zig");
const Duration = @import("./duration.zig");

/// Semitones from A4, resolved to Hz at A4 = 440 Hz.
const Pitch = struct {
    semitones: i32,

    pub const ResolveT = f64;

    pub fn resolve(self: Pitch, ctx: Context) ResolveT {
        _ = ctx;
        return 440.0 * std.math.pow(f64, 2.0, @as(f64, @floatFromInt(self.semitones)) / 12.0);
    }
};

/// The energy given to a vibrating body. Rejects a negative value.
const Volume = struct {
    value: f64 = 1.0,

    pub const ResolveT = f64;

    pub fn resolve(self: Volume, ctx: Context) error{NegativeVolume}!ResolveT {
        _ = ctx;
        if (self.value < 0.0) return error.NegativeVolume;
        return self.value;
    }
};

/// Moves a pitch by a number of semitones.
const Transpose = struct {
    semitones: i32,

    fn apply(self: Transpose, pitch: Pitch) Pitch {
        return .{ .semitones = pitch.semitones + self.semitones };
    }
};

// 120 BPM, 44100 Hz: a beat is 22050 frames.
const test_ctx: Context = .{ .bpm = 120, .sample_rate = 44100 };

test "zip pairs layers by name, and the order does not change the type" {
    const Score = inner(.{ .timing = Timing, .pitch = Pitch, .volume = Volume });
    const rhythm: inner(.{ .timing = Timing }) = .{ .columns = .{ .timing = &.{ .{ .beat = 0.0 }, .{ .beat = 1.0 } } }, .extent = 2.0 };
    const notes: inner(.{ .pitch = Pitch }) = .{ .columns = .{ .pitch = &.{ .{ .semitones = 0 }, .{ .semitones = 7 } } } };
    const accents: inner(.{ .volume = Volume }) = .{ .columns = .{ .volume = &.{ .{ .value = 1.0 }, .{ .value = 0.5 } } } };

    const allocator = std.testing.allocator;
    const score = try (try rhythm.zip(allocator, notes)).zip(allocator, accents);
    const reordered = try (try accents.zip(allocator, notes)).zip(allocator, rhythm);
    comptime std.debug.assert(@TypeOf(score) == Score);
    comptime std.debug.assert(@TypeOf(reordered) == Score);
    comptime std.debug.assert(inner(.{ .volume = Volume, .pitch = Pitch, .timing = Timing }) == Score);

    try std.testing.expectEqual(@as(usize, 2), score.count());
    try std.testing.expectEqual(@as(f64, 2.0), score.extent);
}

test "zip returns an error for different counts" {
    const allocator = std.testing.allocator;
    const rhythm: inner(.{ .timing = Timing }) = .{ .columns = .{ .timing = &.{ .{}, .{ .beat = 1.0 } } } };
    const notes: inner(.{ .pitch = Pitch }) = .{ .columns = .{ .pitch = &.{ .{ .semitones = 0 }, .{ .semitones = 7 }, .{ .semitones = 12 } } } };
    try std.testing.expectError(error.MismatchedCount, rhythm.zip(allocator, notes));
    try std.testing.expectError(error.MismatchedCount, notes.zip(allocator, rhythm));
}

test "zip broadcasts a layer of one element that is not placed in time, on either side" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const cell: inner(.{ .timing = Timing }) = .{ .columns = .{ .timing = &.{ .{}, .{ .beat = 0.5 } } }, .extent = 1.0 };
    const rhythm = try cell.repeat(allocator, 2);
    const e2: inner(.{ .pitch = Pitch }) = .{ .columns = .{ .pitch = &.{.{ .semitones = -29 }} } };

    const melody = try rhythm.zip(allocator, e2);
    const reordered = try e2.zip(allocator, rhythm);
    comptime std.debug.assert(@TypeOf(melody) == @TypeOf(reordered));
    try std.testing.expectEqualDeep(melody, reordered);

    try std.testing.expectEqual(@as(usize, 4), melody.count());
    for (melody.columns.pitch) |pitch| try std.testing.expectEqual(@as(i32, -29), pitch.semitones);
    try std.testing.expectEqual(rhythm.columns.timing, melody.columns.timing);
}

test "a broadcast keeps the extent and origins of the other layer" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const cell: inner(.{ .timing = Timing }) = .{ .columns = .{ .timing = &.{ .{}, .{ .beat = 0.5 } } }, .extent = 1.0 };
    const rhythm = try cell.repeat(allocator, 2);
    const loud: inner(.{ .volume = Volume }) = .{ .columns = .{ .volume = &.{.{ .value = 0.8 }} } };

    for ([_]@TypeOf(try rhythm.zip(allocator, loud)){ try rhythm.zip(allocator, loud), try loud.zip(allocator, rhythm) }) |accented| {
        try std.testing.expectEqual(@as(f64, 2.0), accented.extent);
        try std.testing.expectEqualSlices(f64, &.{ 0, 0, 1, 1 }, accented.origins);
    }
}

test "zip does not broadcast a layer of one element placed in time" {
    const allocator = std.testing.allocator;
    const notes: inner(.{ .pitch = Pitch }) = .{ .columns = .{ .pitch = &.{ .{ .semitones = 0 }, .{ .semitones = 7 } } } };

    // One chord that lasts two bars, like the ending of a piece.
    const long: inner(.{ .timing = Timing }) = .{ .columns = .{ .timing = &.{.{}} }, .extent = 8.0 };
    try std.testing.expectError(error.MismatchedCount, notes.zip(allocator, long));
    try std.testing.expectError(error.MismatchedCount, long.zip(allocator, notes));

    // Placed by its origins alone.
    const late: inner(.{ .timing = Timing }) = .{ .columns = .{ .timing = &.{.{}} }, .origins = &.{4.0} };
    try std.testing.expectError(error.MismatchedCount, notes.zip(allocator, late));
    try std.testing.expectError(error.MismatchedCount, late.zip(allocator, notes));
}

test "a broadcast onto a layer of no elements gives no elements" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const rest = inner(.{ .timing = Timing }).empty(4.0);
    const e2: inner(.{ .pitch = Pitch }) = .{ .columns = .{ .pitch = &.{.{ .semitones = -29 }} } };
    for ([_]@TypeOf(try rest.zip(allocator, e2)){ try rest.zip(allocator, e2), try e2.zip(allocator, rest) }) |silence| {
        try std.testing.expectEqual(@as(usize, 0), silence.count());
        try std.testing.expectEqual(@as(f64, 4.0), silence.extent);
    }

    // A layer of one element placed in time is not broadcast, even onto no elements.
    const long: inner(.{ .pitch = Pitch }) = .{ .columns = .{ .pitch = &.{.{ .semitones = -29 }} }, .extent = 8.0 };
    try std.testing.expectError(error.MismatchedCount, rest.zip(allocator, long));
    try std.testing.expectError(error.MismatchedCount, long.zip(allocator, rest));
}

test "zip allocates nothing without a broadcast" {
    const allocator = std.testing.failing_allocator;
    const rhythm: inner(.{ .timing = Timing }) = .{ .columns = .{ .timing = &.{ .{}, .{ .beat = 1.0 } } }, .extent = 2.0 };
    const notes: inner(.{ .pitch = Pitch }) = .{ .columns = .{ .pitch = &.{ .{ .semitones = 0 }, .{ .semitones = 7 } } } };

    const melody = try rhythm.zip(allocator, notes);
    try std.testing.expectEqual(rhythm.columns.timing.ptr, melody.columns.timing.ptr);
    try std.testing.expectEqual(notes.columns.pitch.ptr, melody.columns.pitch.ptr);
}

test "a broadcast returns the error of the allocator" {
    const allocator = std.testing.failing_allocator;
    const notes: inner(.{ .pitch = Pitch }) = .{ .columns = .{ .pitch = &.{ .{ .semitones = 0 }, .{ .semitones = 7 } } } };
    const loud: inner(.{ .volume = Volume }) = .{ .columns = .{ .volume = &.{.{ .value = 0.8 }} } };
    try std.testing.expectError(error.OutOfMemory, notes.zip(allocator, loud));
    try std.testing.expectError(error.OutOfMemory, loud.zip(allocator, notes));
}

test "a broadcast copies every primitive of the element" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const rhythm: inner(.{ .timing = Timing }) = .{ .columns = .{ .timing = &.{ .{}, .{ .beat = 1.0 }, .{ .beat = 2.0 } } }, .extent = 3.0 };
    const accented_e2: inner(.{ .pitch = Pitch, .volume = Volume }) = .{
        .columns = .{ .pitch = &.{.{ .semitones = -29 }}, .volume = &.{.{ .value = 0.8 }} },
    };

    const melody = try rhythm.zip(allocator, accented_e2);
    try std.testing.expectEqual(@as(usize, 3), melody.count());
    for (melody.columns.pitch, melody.columns.volume) |pitch, volume| {
        try std.testing.expectEqual(@as(i32, -29), pitch.semitones);
        try std.testing.expectEqual(@as(f64, 0.8), volume.value);
    }
}

test "a broadcast onto a layer not placed in time is not placed in time" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const notes: inner(.{ .pitch = Pitch }) = .{ .columns = .{ .pitch = &.{ .{ .semitones = 0 }, .{ .semitones = 7 }, .{ .semitones = 12 } } } };
    const loud: inner(.{ .volume = Volume }) = .{ .columns = .{ .volume = &.{.{ .value = 0.8 }} } };

    for ([_]@TypeOf(try notes.zip(allocator, loud)){ try notes.zip(allocator, loud), try loud.zip(allocator, notes) }) |accented| {
        try std.testing.expectEqual(@as(usize, 3), accented.count());
        try std.testing.expectEqual(@as(f64, 0.0), accented.extent);
        try std.testing.expectEqual(@as(usize, 0), accented.origins.len);
    }
}

test "zip keeps the timeline of the layer that is placed in time" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const cell: inner(.{ .timing = Timing }) = .{ .columns = .{ .timing = &.{.{}} }, .extent = 1.0 };
    const rhythm = try cell.repeat(allocator, 2);
    const note: inner(.{ .pitch = Pitch }) = .{ .columns = .{ .pitch = &.{.{ .semitones = 0 }} } };
    const notes = try note.repeat(allocator, 2);

    const melody = try notes.zip(allocator, rhythm);
    try std.testing.expectEqual(@as(f64, 2.0), melody.extent);
    try std.testing.expectEqualSlices(f64, &.{ 0.0, 1.0 }, melody.origins);
}

test "zip rejects two different timelines" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const cell: inner(.{ .timing = Timing }) = .{ .columns = .{ .timing = &.{.{}} }, .extent = 1.0 };
    const accent: inner(.{ .volume = Volume }) = .{ .columns = .{ .volume = &.{.{}} }, .extent = 2.0 };
    try std.testing.expectError(error.MismatchedExtent, cell.zip(allocator, accent));

    // Same extents, different origins.
    const two_cells = try cell.repeat(allocator, 2);
    const late: inner(.{ .volume = Volume }) = .{ .columns = .{ .volume = &.{ .{}, .{} } }, .extent = 2.0, .origins = &.{ 0.0, 0.5 } };
    try std.testing.expectError(error.MismatchedExtent, two_cells.zip(allocator, late));
}

test "concat places the second layer after the extent of the first" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // A gallop: an eighth and two sixteenths, one beat long.
    const Rhythm = inner(.{ .timing = Timing, .duration = Duration });
    const gallop: Rhythm = .{
        .columns = .{
            .timing = &.{ .{ .beat = 0.0 }, .{ .beat = 0.5 }, .{ .beat = 0.75 } },
            .duration = &.{ .{ .beats = 0.5 }, .{ .beats = 0.25 }, .{ .beats = 0.25 } },
        },
        .extent = 1.0,
    };

    const two = try gallop.concat(allocator, gallop);
    try std.testing.expectEqual(@as(usize, 6), two.count());
    try std.testing.expectEqual(@as(f64, 2.0), two.extent);

    const resolved = try two.resolve(allocator, test_ctx);
    const starts = [_]usize{ 0, 11025, 16538, 22050, 33075, 38588 };
    for (resolved, starts) |event, start| try std.testing.expectEqual(start, event.timing);
    try std.testing.expectEqual(@as(usize, 11025), resolved[3].duration);
}

test "concat of layers that are not placed in time only appends" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const notes: inner(.{ .pitch = Pitch }) = .{ .columns = .{ .pitch = &.{ .{ .semitones = 0 }, .{ .semitones = 7 } } } };
    const four = try notes.concat(allocator, notes);
    try std.testing.expectEqual(@as(usize, 4), four.count());
    try std.testing.expectEqual(@as(f64, 0.0), four.extent);
    try std.testing.expectEqual(@as(usize, 0), four.origins.len);
}

test "an empty layer is silence of its extent" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const Rhythm = inner(.{ .timing = Timing });
    const hit: Rhythm = .{ .columns = .{ .timing = &.{.{}} }, .extent = 1.0 };
    const late = try Rhythm.empty(3.0).concat(allocator, hit);
    try std.testing.expectEqual(@as(usize, 1), late.count());
    try std.testing.expectEqual(@as(f64, 4.0), late.extent);

    const resolved = try late.resolve(allocator, test_ctx);
    try std.testing.expectEqual(@as(usize, 3 * 22050), resolved[0].timing);
}

test "repeat concatenates a layer with itself" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const Rhythm = inner(.{ .timing = Timing });
    const cell: Rhythm = .{ .columns = .{ .timing = &.{ .{}, .{ .beat = 0.5 } } }, .extent = 1.0 };
    const bar = try cell.repeat(allocator, 4);
    try std.testing.expectEqual(@as(usize, 8), bar.count());
    try std.testing.expectEqual(@as(f64, 4.0), bar.extent);
    try std.testing.expectEqualSlices(f64, &.{ 0, 0, 1, 1, 2, 2, 3, 3 }, bar.origins);

    const none = try cell.repeat(allocator, 0);
    try std.testing.expectEqual(@as(usize, 0), none.count());
    try std.testing.expectEqual(@as(f64, 0.0), none.extent);
}

test "map transforms one primitive and keeps the others" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const rhythm: inner(.{ .timing = Timing }) = .{ .columns = .{ .timing = &.{ .{}, .{ .beat = 1.0 } } }, .extent = 2.0 };
    const notes: inner(.{ .pitch = Pitch }) = .{ .columns = .{ .pitch = &.{ .{ .semitones = 0 }, .{ .semitones = 7 } } } };
    const melody = try rhythm.zip(allocator, notes);

    const up = try melody.map(allocator, .pitch, Transpose{ .semitones = 12 });
    try std.testing.expectEqual(@as(i32, 12), up.columns.pitch[0].semitones);
    try std.testing.expectEqual(@as(i32, 19), up.columns.pitch[1].semitones);
    try std.testing.expectEqual(melody.columns.timing, up.columns.timing);
    try std.testing.expectEqual(@as(f64, 2.0), up.extent);
    // The input is not changed.
    try std.testing.expectEqual(@as(i32, 0), melody.columns.pitch[0].semitones);
}

test "resolve returns one named value per primitive" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const rhythm: inner(.{ .timing = Timing }) = .{ .columns = .{ .timing = &.{ .{}, .{ .beat = 1.0 } } } };
    const notes: inner(.{ .pitch = Pitch }) = .{ .columns = .{ .pitch = &.{ .{ .semitones = 0 }, .{ .semitones = 12 } } } };
    const resolved = try (try rhythm.zip(allocator, notes)).resolve(allocator, test_ctx);

    try std.testing.expectEqual(@as(usize, 0), resolved[0].timing);
    try std.testing.expectEqual(@as(f64, 440.0), resolved[0].pitch);
    try std.testing.expectEqual(@as(usize, 22050), resolved[1].timing);
    try std.testing.expectEqual(@as(f64, 880.0), resolved[1].pitch);
}

test "resolve returns the error of a primitive" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const accents: inner(.{ .volume = Volume }) = .{ .columns = .{ .volume = &.{ .{ .value = 1.0 }, .{ .value = -1.0 } } } };
    try std.testing.expectError(error.NegativeVolume, accents.resolve(allocator, test_ctx));

    const rhythm: inner(.{ .timing = Timing }) = .{ .columns = .{ .timing = &.{.{ .beat = -1.0 }} } };
    try std.testing.expectError(error.InvalidPosition, rhythm.resolve(allocator, test_ctx));
}

test {
    std.testing.refAllDecls(@This());
}
