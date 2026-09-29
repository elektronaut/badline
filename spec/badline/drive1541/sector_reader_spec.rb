# frozen_string_literal: true

require "spec_helper"

describe Badline::Drive1541::SectorReader do
  let(:disk) { Badline::Drive1541::Disk }
  let(:gcr) { Badline::Drive1541::GCR }
  let(:data) { Array.new(256) { |i| (i * 11) & 0xff } }

  # A sector as the DOS writes it: SYNC, header, gap, SYNC and data.
  def sector_bits(track, sector, data, id: [0x41, 0x42])
    bytes = [0xff] * 5
    bytes.concat(gcr.encode(disk.header(track, sector, id, nil)))
    bytes.concat([0x55] * 9, [0xff] * 5)
    bytes.concat(gcr.encode(disk.data_block(data, nil)))
    bytes.map { |byte| format("%08b", byte) }.join
  end

  def track_bytes(bits)
    [bits].pack("B*").bytes
  end

  # A track of gap bytes with the bits written over it from +offset+,
  # wrapping round past the end.
  def written(bits, offset, length: 7142)
    track = ("01010101" * length).dup
    bits.each_char.with_index { |bit, i| track[(offset + i) % track.length] = bit }
    track_bytes(track)
  end

  it "reads a sector written at a bit offset the stored bytes don't line up with" do
    sector = described_class.read(written(sector_bits(18, 4, data), 1003), 18)[4]
    expect([sector.header[0, 4], sector.data[1, 256]]).to eq([[0x08, 4 ^ 18 ^ 0x42 ^ 0x41, 4, 18], data])
  end

  it "reads a sector that runs on past the end of the track" do
    bits = sector_bits(18, 7, data)
    sector = described_class.read(written(bits, (7142 * 8) - 1500), 18)[7]
    expect(sector.data[1, 256]).to eq(data)
  end

  it "leaves out a header for another track" do
    expect(described_class.read(written(sector_bits(17, 4, data), 16), 18)).to be_empty
  end

  it "finds nothing on a track without flux" do
    expect(described_class.read(Array.new(100, 0), 18)).to be_empty
  end

  it "finds nothing on a track that is all SYNC" do
    expect(described_class.read(Array.new(100, 0xff), 18)).to be_empty
  end

  # Sector 2's data block is missing, so the block after its header is
  # sector 3's header, which runs into a SYNC mark before a data block's
  # length.
  it "takes the block after a header as its data block" do
    header_only = sector_bits(18, 2, data)[0, (5 + 10 + 9) * 8]
    found = described_class.read(written(header_only + sector_bits(18, 3, data), 0), 18)
    expect([found[2].data, found[3].data[1, 256]]).to eq([nil, data])
  end
end
