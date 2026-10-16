# frozen_string_literal: true

# Freshly formatted disk images, as the DOS's NEW command leaves them: every
# block free but the header, the BAM and the first directory block, and an
# empty directory. Each writes the image to the path and returns it.
module BlankDisk
  D64_SECTORS = ([21] * 17) + ([19] * 7) + ([18] * 6) + ([17] * 5)
  D80_SECTORS = ([29] * 39) + ([27] * 14) + ([25] * 11) + ([23] * 13)

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

  # As VICE's c1541 formats them: the header at 39/0, an empty directory
  # at 39/1, and the BAM in blocks 0 and 3 of track 38, and 6 and 9 on an
  # 8250, each covering 50 tracks.
  def blank_d80(path, name: "BLANK", id: "AB", sides: 1)
    sectors = D80_SECTORS * sides
    bytes = Array.new(sectors.sum * 256, 0)
    offset = ->(track, sector) { (sectors.first(track - 1).sum + sector) * 256 }
    bytes[offset[39, 0], 3] = [38, 0, 0x43]
    bytes[offset[39, 0] + 0x06, 27] = padded(name) + [0xa0, 0xa0] + id.bytes + [0xa0, 0x32, 0x43] + ([0xa0] * 4)
    bytes[offset[39, 1], 2] = [0, 0xff]
    groups = (1..sectors.length).each_slice(50).to_a
    groups.each_with_index do |tracks, block|
      bam = offset[38, 3 * block]
      link = block == groups.length - 1 ? [39, 1] : [38, 3 * (block + 1)]
      bytes[bam, 6] = link + [0x43, 0, tracks.first, tracks.last + 1]
      tracks.each_with_index do |track, i|
        used = { 38 => (0...groups.length).map { |b| 3 * b }, 39 => [0, 1] }.fetch(track, [])
        count = sectors[track - 1]
        bytes[bam + 6 + (5 * i), 5] = [count - used.length, *free_bitmap(count, used, 4)]
      end
    end
    File.binwrite(path, bytes.pack("C*"))
    path
  end

  def blank_d82(path, name: "BLANK", id: "AB") = blank_d80(path, name:, id:, sides: 2)

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
