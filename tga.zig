const builtin = @import("builtin");
const std = @import("std");
const image = @import("image.zig");

pub const PreloadedInfo = struct {
  id_length: u8,
  colormap_type: u8,
  image_type: u8,
  colormap_index: u16,
  colormap_length: u16,
  colormap_size: u8,
  x_origin: u16,
  y_origin: u16,
  width: u16,
  height: u16,
  pixel_size: u8,
  attr_bits: u4,
  reserved: u1,
  origin: u1,
  interleaving: u2,
};

pub fn tgaBestStoreFormat(tgaInfo: *const TgaInfo) image.Format {
  if (tgaInfo.attr_bits > 0) {
    return image.Format.RGBA;
  } else {
    return image.Format.RGB;
  }
}

pub fn preload(comptime ReadError: type, stream: *std.io.InStream(ReadError)) !PreloadedInfo {
  const id_length = try stream.readByte();
  const colormap_type = try stream.readByte();
  const image_type = try stream.readByte();
  const colormap_index = try stream.readIntLe(u16);
  const colormap_length = try stream.readIntLe(u16);
  const colormap_size = try stream.readByte();
  const x_origin = try stream.readIntLe(u16);
  const y_origin = try stream.readIntLe(u16);
  const width = try stream.readIntLe(u16);
  const height = try stream.readIntLe(u16);
  const pixel_size = try stream.readByte();
  const descriptor = try stream.readByte();

  const attr_bits = @truncate(u4, descriptor & 0x0F);
  const reserved = @truncate(u1, (descriptor & 0x10) >> 4);
  const origin = @truncate(u1, (descriptor & 0x20) >> 5);
  const interleaving = @truncate(u2, (descriptor & 0xC0) >> 6);

  if (colormap_type != 0) {
    return error.Unsupported; // TODO
  }
  if (reserved != 0) {
    return error.Corrupt;
  }
  if (interleaving != 0) {
    return error.Unsupported;
  }

  switch (image_type) {
    else => return error.Corrupt,
    0 => return error.Unsupported, // no image data included
    1, 9 => return error.Unsupported, // colormapped (TODO)
    3, 11 => return error.Unsupported, // greyscale (TODO)
    32, 33 => return error.Unsupported,
    2, 10 => {
      if (pixel_size == 16) {
        if (attr_bits != 1) {
          return error.Corrupt;
        }
      } else if (pixel_size == 24) {
        if (attr_bits != 0) {
          return error.Corrupt;
        }
      } else if (pixel_size == 32) {
        if (attr_bits != 8) {
          return error.Corrupt;
        }
      } else {
        return error.Corrupt;
      }
    },
  }

  var i: usize = 0;
  while (i < id_length) : (i += 1) {
    _ = try stream.readByte();
  }

  return PreloadedInfo{
    .id_length = id_length,
    .colormap_type = colormap_type,
    .image_type = image_type,
    .colormap_index = colormap_index,
    .colormap_length = colormap_length,
    .colormap_size = colormap_size,
    .x_origin = x_origin,
    .y_origin = y_origin,
    .width = width,
    .height = height,
    .pixel_size = pixel_size,
    .attr_bits = attr_bits,
    .reserved = reserved,
    .origin = origin,
    .interleaving = interleaving,
  };
}

const Pixel = struct {
  r: u8,
  g: u8,
  b: u8,
  a: u8,
};

pub fn loadIntoRGB(
  comptime ReadError: type,
  stream: *std.io.InStream(ReadError),
  preloaded: *const PreloadedInfo,
  out_buffer: []u8,
) !void {
  const width = preloaded.width;
  const height = preloaded.height;
  if (out_buffer.len < width * height * 3) {
    return error.TgaLoadFailed;
  }

  var out: usize = 0;

  switch (preloaded.image_type) {
    else => unreachable,
    2, 10 => {
      const compressed = preloaded.image_type == 10;

      const num_pixels = width * height;

      var i: u32 = 0;

      while (i < num_pixels) {
        var run_length: u32 = undefined;
        var is_raw_packet: bool = undefined;

        if (compressed) {
          const run_header = try stream.readByte();

          run_length = 1 + (run_header & 0x7f);
          is_raw_packet = (run_header & 0x80) == 0;
        } else {
          run_length = 1;
          is_raw_packet = true;
        }

        if (i + run_length > num_pixels) {
          return error.Corrupt;
        }

        var j: u32 = 0;

        if (is_raw_packet) {
          while (j < run_length) : (j += 1) {
            const pixel = try readPixel(preloaded.pixel_size, ReadError, stream);
            if (out + 3 > out_buffer.len) {
              // @compileError("ASD");
              return error.TgaLoadFailed;
            }
            out_buffer[out] = pixel.r; out += 1;
            out_buffer[out] = pixel.g; out += 1;
            out_buffer[out] = pixel.b; out += 1;
          }
        } else {
          const pixel = try readPixel(preloaded.pixel_size, ReadError, stream);

          while (j < run_length) : (j += 1) {
            if (out + 3 > out_buffer.len) {
              // @compileError("ASD");
              return error.TgaLoadFailed;
            }
            out_buffer[out] = pixel.r; out += 1;
            out_buffer[out] = pixel.g; out += 1;
            out_buffer[out] = pixel.b; out += 1;
          }
        }

        i += run_length;
      }
    },
  }

  if (preloaded.origin == 0) {
    image.flipVertical(width, height, 3, out_buffer);
  }
}

fn readPixel(
  pixelSize: u8,
  comptime ReadError: type,
  stream: *std.io.InStream(ReadError),
) !Pixel {
  switch (pixelSize) {
    16 => {
      var p: [2]u8 = undefined;
      std.debug.assert(2 == try stream.read(p[0..]));
      const r = (p[1] & 0x7C) >> 2;
      const g = ((p[1] & 0x03) << 3) | ((p[0] & 0xE0) >> 5);
      const b = (p[0] & 0x1F);
      const a = (p[1] & 0x80) >> 7;
      return Pixel{
        .r = (r << 3) | (r >> 2),
        .g = (g << 3) | (g >> 2),
        .b = (b << 3) | (b >> 2),
        .a = a * 0xFF,
      };
    },
    24 => {
      var bgr: [3]u8 = undefined;
      std.debug.assert(3 == try stream.read(bgr[0..]));
      return Pixel{ .r = bgr[2], .g = bgr[1], .b = bgr[0], .a = 255 };
    },
    32 => {
      var bgra: [4]u8 = undefined;
      std.debug.assert(4 == try stream.read(bgra[0..]));
      return Pixel{ .r = bgra[2], .g = bgra[1], .b = bgra[0], .a = bgra[3] };
    },
    else => unreachable,
  }
}
