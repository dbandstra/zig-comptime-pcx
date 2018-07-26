const std = @import("std");
const tga = @import("tga.zig");
const util = @import("util.zig");

test "load tga at compile time" {
  comptime {
    @setEvalBranchQuota(20000);

    const input = @embedFile("space_merc.tga");
    var slice_stream = std.io.SliceStream.init(input);
    var stream = &slice_stream.stream;
    const preloaded = try tga.preload(std.io.SliceStream.Error, stream);
    var rgb: [preloaded.width * preloaded.height * 3]u8 = undefined;
    try tga.loadIntoRGB(std.io.SliceStream.Error, stream, &preloaded, rgb[0..]);

    var greyscale: [preloaded.width * preloaded.height]u8 = undefined;
    util.convertToGreyscale(rgb, greyscale[0..]);
    var string: [(preloaded.width+1)*preloaded.height]u8 = undefined;
    var i: usize = 0;
    var y: usize = 0;
    while (y < preloaded.height) : (y += 1) {
      string[i] = '\n'; i += 1;
      var x: usize = 0;
      while (x < preloaded.width) : (x += 1) {
        const shade256 = greyscale[y*preloaded.width+x];
        const quant = @divFloor(shade256, 26);
        string[i] = util.grey10[9 - quant]; i += 1;
      }
    }
    @compileLog(string);
  }
}
