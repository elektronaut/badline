# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "badline/drives/model8050"
require_relative "../../../support/blank_disk"

# The layout is DOS 2.7's format code's ($C000-$C363), as it writes a
# track on the controller.
describe Badline::Drives::Model8050::Disk do
  include BlankDisk

  subject(:disk) { described_class.new(Badline::Storage::D80Image.new(blank_d80(path, id: "AB"))) }

  let(:dir) { Dir.mktmpdir }
  let(:path) { File.join(dir, "blank.d80") }
  let(:sync) { described_class::SYNC }

  after { FileUtils.remove_entry(dir) }

  it "holds a turn's cells at 6 MHz / (16 - zone), 10 bits a cell" do
    expect([3, 2, 1, 0].map { |zone| described_class.cells_in(zone) }).to eq([9230, 8571, 8000, 7500])
  end

  it "records tracks 1-39, 40-53, 54-64 and 65-77 in zones 3 to 0, on either side" do
    expect([1, 39, 40, 53, 54, 64, 65, 77, 78, 154].map { |track| described_class.zone_of(track) })
      .to eq([3, 3, 2, 2, 1, 1, 0, 0, 3, 0])
  end

  it "fills a track's turn" do
    expect([1, 40, 54, 77].map { |track| disk.track(track).length }).to eq([9230, 8571, 8000, 7500])
  end

  it "starts each sector with four syncs and the header" do
    cells = disk.track(39)
    expect(cells[0, 11]).to eq([sync, sync, sync, sync, 0x08, 39 ^ 0 ^ 0x41 ^ 0x42, 0, 39, 0x42, 0x41, 0x0f])
  end

  it "follows the header with 20 $0F, four syncs and the data block's $07" do
    expect(disk.track(39)[10, 25]).to eq(Array.new(20, 0x0f) + [sync, sync, sync, sync, 0x07])
  end

  it "ends the data block with the EOR of its bytes" do
    cells = disk.track(39)
    expect(cells[35 + 256]).to eq(disk.image.read_block(39, 0).reduce(0, :^))
  end

  it "has no second side on a .d80" do
    expect(disk.track(78)).to be_nil
  end

  describe "#flush" do
    let(:written) { Array.new(256) { |index| (index * 5) & 0xff } }

    before do
      cells = disk.track(70)
      offset = cells.index(0x07) + 1
      cells[offset, 257] = written + [written.reduce(0, :^)]
      disk.written(70)
      disk.flush
    end

    it "stores the blocks written back in the image" do
      expect(Badline::Storage::D80Image.new(path).read_block(70, 0)).to eq(written)
    end

    it "leaves the other blocks of the track as they were" do
      expect(Badline::Storage::D80Image.new(path).read_block(70, 1)).to eq(Array.new(256, 0))
    end
  end

  it "skips a block whose checksum doesn't match" do
    cells = disk.track(70)
    cells[cells.index(0x07) + 1] = 0x99
    disk.written(70)
    disk.flush
    expect(Badline::Storage::D80Image.new(path).read_block(70, 0)).to eq(Array.new(256, 0))
  end
end
