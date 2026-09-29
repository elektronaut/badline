# frozen_string_literal: true

# Freshly formatted disk images, as the DOS's NEW command leaves them: every
# block free but the header, the BAM and the first directory block, and an
# empty directory. Each writes the image to the path and returns it.
module BlankDisk
  D64_SECTORS = ([21] * 17) + ([19] * 7) + ([18] * 6) + ([17] * 5)

  def blank_d64(path, name: "BLANK")
    bytes = Array.new(174_848, 0)
    D64_SECTORS.each_with_index do |sectors, i|
      free = i == 17 ? sectors - 2 : sectors
      bytes[d64_offset(18, 0) + 4 + (4 * i), 4] = [free, *free_bitmap(sectors, i == 17 ? [0, 1] : [], 3)]
    end
    bytes[d64_offset(18, 0), 3] = [18, 1, 0x41]
    bytes[d64_offset(18, 0) + 0x90, 16] = padded(name)
    bytes[d64_offset(18, 1), 2] = [0, 0xff]
    File.binwrite(path, bytes.pack("C*"))
    path
  end

  def blank_d81(path, name: "BLANK")
    bytes = Array.new(819_200, 0)
    offset = ->(sector) { ((39 * 40) + sector) * 256 }
    bytes[offset[0], 3] = [40, 3, 0x44]
    bytes[offset[0] + 0x04, 16] = padded(name)
    bytes[offset[1], 2] = [40, 2]
    bytes[offset[2], 2] = [0, 0xff]
    [1, 2].each do |block|
      40.times do |i|
        used = block == 1 && i == 39 ? [0, 1, 2, 3] : []
        bytes[offset[block] + 0x10 + (6 * i), 6] = [40 - used.length, *free_bitmap(40, used, 5)]
      end
    end
    bytes[offset[3], 2] = [0, 0xff]
    File.binwrite(path, bytes.pack("C*"))
    path
  end

  def d64_offset(track, sector)
    (D64_SECTORS.first(track - 1).sum + sector) * 256
  end

  private

  def padded(name) = name.bytes + ([0xa0] * (16 - name.length))

  def free_bitmap(sectors, used, length)
    bits = (0...sectors).sum { |s| used.include?(s) ? 0 : 1 << s }
    Array.new(length) { |i| (bits >> (8 * i)) & 0xff }
  end
end
