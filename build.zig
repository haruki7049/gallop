const std = @import("std");
const l = @import("lightmix");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lightmix = b.dependency("lightmix", .{});

    // Modules
    const imports: []const std.Build.Module.Import = &.{
        .{ .name = "lightmix", .module = lightmix.module("lightmix") },
    };
    const mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = imports,
    });

    // Wave file installation
    const wave = try l.addWave(b, mod, .{
        .optimize = optimize,
        .format = .{ .wav = .{
            .bits = 16,
            .format_code = .pcm,
            .name = "coffee-chan.wav",
        } },
    });
    l.installWave(b, wave);

    const play_step = b.step("play", "Play the produced Wave file");
    const play = try l.addPlay(b, wave, .{});
    play_step.dependOn(&play.step);

    // Tests
    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    // Test step
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);

    // Sandbox
    const sandbox_step = b.step("sandbox", "Generate wav files on sandbox");
    try build_sandbox(b, target, optimize, imports, sandbox_step);
}

fn build_sandbox(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    imports: []const std.Build.Module.Import,
    sandbox_step: *std.Build.Step,
) !void {
    const paths_names: []const struct { []const u8, []const u8 } = &.{
        // .{ "sandbox/karplus-strong/mono-440.0.zig", "karplus-strong-mono-440.0.wav" },
        // .{ "sandbox/karplus-strong/mono-bass-110.0.zig", "karplus-strong-mono-bass-110.0.wav" },
        // .{ "sandbox/sine/mono-440.0.zig", "sine-mono-440.0.wav" },
        // .{ "sandbox/sine/stereo-440.0.zig", "sine-stereo-440.0.wav" },
    };

    inline for (paths_names) |pn| {
        const path = pn.@"0";
        const name = pn.@"1";

        const mod = b.createModule(.{
            .root_source_file = b.path(path),
            .target = target,
            .optimize = optimize,
            .imports = imports,
        });

        try add_sandbox_wave(b, optimize, mod, name, sandbox_step);
    }

    // Phrases share a single source file; the phrase is selected through the `phrase_options` module.
    const phrase_ids: []const []const u8 = &.{
        // "0000", "0001", "0002", "0003", "0004", "0005", "0006", "0007"
    };

    inline for (phrase_ids) |id| {
        const mod = b.createModule(.{
            .root_source_file = b.path("sandbox/phrases/phrase.zig"),
            .target = target,
            .optimize = optimize,
            .imports = imports,
        });

        const phrase_options = b.addOptions();
        phrase_options.addOption([]const u8, "phrase", "_" ++ id);
        mod.addOptions("phrase_options", phrase_options);

        try add_sandbox_wave(b, optimize, mod, "phrase-" ++ id ++ ".wav", sandbox_step);
    }
}

fn add_sandbox_wave(
    b: *std.Build,
    optimize: std.builtin.OptimizeMode,
    mod: *std.Build.Module,
    name: []const u8,
    sandbox_step: *std.Build.Step,
) !void {
    const wave = try l.addWave(b, mod, .{
        .optimize = optimize,
        .format = .{ .wav = .{
            .bits = 16,
            .format_code = .pcm,
            .name = name,
        } },
        .path = .{ .custom = "share/sandbox" },
    });
    sandbox_step.dependOn(wave.step);
}
