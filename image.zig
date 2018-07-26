const std = @import("std");

pub fn flipVertical(width: usize, height: usize, bpp: usize, buffer: []u8) void {
  const rb = bpp * width;

  var y: usize = 0;

  while (y < height / 2) : (y += 1) {
    const ofs0 = rb * y;
    const ofs1 = rb * (height - 1 - y);

    const row0 = buffer[ofs0..ofs0 + rb];
    const row1 = buffer[ofs1..ofs1 + rb];

    swapSlices(u8, row0, row1);
  }
}

fn swapSlices(comptime T: type, a: []T, b: []T) void {
  std.debug.assert(a.len == b.len);
  var i: usize = 0;
  while (i < a.len) : (i += 1) {
    const value = a[i];
    a[i] = b[i];
    b[i] = value;
  }
}
