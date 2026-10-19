# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

describe Badline::Storage::D67Image do
  subject(:image) { described_class.new(path) }

  let(:dir) { Dir.mktmpdir }
  let(:path) do
    File.join(dir, "blank.d67").tap do |file|
      File.binwrite(file, "\0" * 176_640)
      described_class.new(file).format("blank d67", "AB".bytes)
    end
  end

  # 18/0, the header and the BAM: track 18 is the 358th block.
  def header = File.binread(path).bytes[357 * 256, 256]

  after { FileUtils.remove_entry(dir) }

  it "holds 21, 20, 18 and 17 sectors in the four zones" do
    expect([1, 17, 18, 24, 25, 30, 31, 35].map { |track| image.sectors_in(track) })
      .to eq([21, 21, 20, 20, 18, 18, 17, 17])
  end

  it "writes the BAM's head as DOS 1 and c1541 do, the format byte $01" do
    expect(header[0, 8]).to eq([0x12, 0x01, 0x01, 0x00, 0x15, 0xff, 0xff, 0x1f])
  end

  it "frees all of track 18 but the header and the directory" do
    expect(header[0x48, 4]).to eq([0x12, 0xfc, 0xff, 0x0f])
  end

  it "puts two spaces after the ID, where DOS 2 has its type" do
    expect(header[0x90, 27]).to eq("BLANK D67".bytes + ([0xa0] * 9) + "AB".bytes + [0x20, 0x20] + ([0xa0] * 5))
  end

  it "counts 670 blocks free" do
    expect(image.directory.blocks_free).to eq(670)
  end

  it "has no block past track 35's 17 sectors" do
    expect([image.read_block(35, 16)&.length, image.read_block(35, 17)]).to eq([256, nil])
  end
end
