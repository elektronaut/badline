# frozen_string_literal: true

# A two-song .sid built from a few bytes of 6502. init sets up a triangle
# voice but gates it only when the song index is non-zero, so the rendered
# audio says which subtune ran. play is an RTS.
module TinySID
  module_function

  def bytes(signature: "PSID", load_address: 0x1000, play: load_address + 0x40, flags: 0x04)
    (header(signature, load_address, play, flags) + image).pack("C*")
  end

  def write(addr, value) = [0xa9, value, 0x8d, addr & 0xff, addr >> 8]

  def init
    [0xaa] + write(0xd418, 0x0f) + write(0xd400, 0x21) + write(0xd401, 0x11) +
      write(0xd405, 0x00) + write(0xd406, 0xf0) +
      [0x8a, 0xf0, 0x05] + write(0xd404, 0x11) + [0x60]
  end

  def image
    init + ([0xea] * (0x40 - init.length)) + [0x60]
  end

  def header(signature, load_address, play, flags)
    fields = { version: 2, data_offset: 0x7c, load: load_address,
               init: load_address, play:, songs: 2, start_song: 1 }
    words = fields.values.flat_map { |value| [value >> 8, value & 0xff] }
    signature.bytes + words + ([0] * 4) + texts +
      [0x00, flags, 0x00, 0x01, 0x00, 0x00]
  end

  def texts
    %w[TUNE AUTHOR 1987].flat_map { |t| t.bytes + ([0] * (32 - t.length)) }
  end
end
