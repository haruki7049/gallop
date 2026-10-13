//! gallop

const std = @import("std");
const lightmix = @import("lightmix");

const configs = @import("./configs.zig");

pub fn gen(init: std.process.Init) !lightmix.Wave(configs.T) {}
