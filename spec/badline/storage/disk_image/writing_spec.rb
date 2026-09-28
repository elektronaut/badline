# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../../support/blank_disk"

describe Badline::Storage::DiskImage::Writing do
  include BlankDisk

  subject(:image) { Badline::Storage::D64Image.new(path) }

  let(:dir) { Dir.mktmpdir }
  let(:path) { File.join(dir, "blank.d64") }
  let(:program) { [0x01, 0x08, *Array.new(600) { |i| i & 0xff }] }

  before { blank_d64(path) }

  after { FileUtils.remove_entry(dir) }

  # The image as the host file now holds it
  def reread = Badline::Storage::D64Image.new(path)

  def blocks_free
    bam = reread.read_block(18, 0)
    (1..35).sum { |track| track == 18 ? 0 : bam[4 * track] }
  end

  # The DOS error a write fails with, or nil when it succeeds
  def dos_error
    yield
    nil
  rescue Badline::Storage::WriteError => e
    e.code
  end

  def directory_entry(index)
    reread.read_block(18, 1)[index * 32, 32]
  end

  describe "#write_file" do
    before { image.write_file("hello", program) }

    it "writes the file to the host file" do
      expect(reread.read_file("hello")).to eq(program)
    end

    it "lays the chain out from the track below the directory, ten sectors apart" do
      chain = [reread.first_block("hello"), reread.read_block(17, 0).first(2), reread.last_block("hello")]
      expect(chain).to eq([[17, 0], [17, 10], [17, 20]])
    end

    it "ends the chain with the index of the last byte" do
      expect(reread.read_block(17, 20).first(2)).to eq([0, 602 - 508 + 1])
    end

    it "takes the blocks from the BAM" do
      expect(blocks_free).to eq(664 - 3)
    end

    it "marks the blocks in use" do
      expect([reread.block_free?(17, 0), reread.block_free?(17, 10), reread.block_free?(17, 1)])
        .to eq([false, false, true])
    end

    it "adds a closed PRG entry with the name padded and the length in blocks" do
      expect(directory_entry(0)[2..]).to eq([0x82, 17, 0, *"HELLO".bytes, *[0xa0] * 11, *[0] * 9, 3, 0])
    end

    it "puts the next file in the next slot" do
      image.write_file("notes", [0x41], type: :seq)
      expect(reread.read_file("notes", type: :seq)).to eq([0x41])
    end

    it "gives an empty file one block" do
      image.write_file("empty", [], type: :seq)
      expect(reread.read_file("empty", type: :seq)).to eq([])
    end

    it "fails a name on the disk as FILE EXISTS" do
      expect(dos_error { image.write_file("HELLO", [1, 8], type: :seq) }).to eq(63)
    end

    it "matches the name exactly, not as a pattern" do
      expect { image.write_file("hel*", [1, 8]) }.not_to raise_error
    end
  end

  describe "a replace" do
    before do
      image.write_file("hello", program)
      image.write_file("hello", [0x01, 0x08, 0x42], replace: true)
    end

    it "writes the new contents" do
      expect(reread.read_file("hello")).to eq([0x01, 0x08, 0x42])
    end

    it "keeps the directory slot" do
      expect(directory_entry(1)[2]).to eq(0)
    end

    it "frees the old blocks" do
      expect(blocks_free).to eq(664 - 1)
    end
  end

  describe "a file too big for the disk" do
    before { image.write_file("hello", program) }

    it "fails as DISK FULL" do
      expect(dos_error { image.write_file("big", Array.new(170_000, 0)) }).to eq(72)
    end

    it "leaves the image as it was" do
      before = File.binread(path)
      dos_error { image.write_file("big", Array.new(170_000, 0)) }
      expect([File.binread(path), image.read_file("big")]).to eq([before, nil])
    end

    it "fills the disk up to the last block" do
      image.write_file("big", Array.new((661 * 254) - 2, 0))
      expect(blocks_free).to eq(0)
    end
  end

  describe "a full directory block" do
    before { 9.times { |i| image.write_file("file#{i}", [1, 8]) } }

    it "links a new block three sectors on" do
      expect(reread.read_block(18, 1).first(2)).to eq([18, 4])
    end

    it "starts the new block as the last one" do
      expect(reread.read_block(18, 4)[0, 4]).to eq([0, 0xff, 0x82, 17])
    end

    it "takes the block from the BAM" do
      expect(reread.block_free?(18, 4)).to be(false)
    end

    it "lists every file" do
      expect(reread.read_file("file8")).to eq([1, 8])
    end
  end

  describe "a full directory" do
    it "fails as DISK FULL" do
      144.times { |i| image.write_file("f#{i}", [1, 8]) }
      expect(dos_error { image.write_file("one more", [1, 8]) }).to eq(72)
    end
  end

  describe "#append_file" do
    before do
      image.write_file("log", Array.new(300, 0x41), type: :seq)
      image.append_file("log", [0x42, 0x43], type: :seq)
    end

    it "adds the bytes to the end" do
      expect(reread.read_file("log", type: :seq)).to eq(Array.new(300, 0x41) + [0x42, 0x43])
    end

    it "keeps the file's type" do
      expect(directory_entry(0)[2]).to eq(0x81)
    end

    it "fails a missing file as FILE NOT FOUND" do
      expect(dos_error { image.append_file("gone", [1]) }).to eq(62)
    end
  end

  describe "#scratch" do
    before do
      %w[game1 game2 other].each { |name| image.write_file(name, program) }
    end

    it "returns how many files matched" do
      expect(image.scratch("game*")).to eq(2)
    end

    it "removes them from the directory" do
      image.scratch("game*")
      expect([reread.read_file("game1"), reread.read_file("other")]).to eq([nil, program])
    end

    it "frees their blocks" do
      image.scratch("game*")
      expect(blocks_free).to eq(664 - 3)
    end

    it "leaves a locked file" do
      bytes = File.binread(path).bytes
      bytes[d64_offset(18, 1) + 2] = 0xc2
      File.binwrite(path, bytes.pack("C*"))
      expect(reread.scratch("game*")).to eq(1)
    end
  end

  describe "#write_block" do
    it "writes the block" do
      image.write_block(1, 0, Array.new(256, 0x5a))
      expect(reread.read_block(1, 0)).to eq(Array.new(256, 0x5a))
    end

    it "leaves the BAM alone" do
      image.write_block(1, 0, Array.new(256, 0x5a))
      expect(reread.block_free?(1, 0)).to be(true)
    end

    context "with an error table" do
      before do
        bytes = File.binread(path).bytes + Array.new(683, 1)
        bytes[-683] = 5 # 23, READ ERROR at 1/0
        File.binwrite(path, bytes.pack("C*"))
      end

      it "clears the block's error" do
        image.write_block(1, 0, Array.new(256, 0))
        expect(reread.block_error(1, 0)).to be_nil
      end

      it "keeps the table in the host file" do
        image.write_block(1, 0, Array.new(256, 0))
        expect(File.size(path)).to eq(175_531)
      end
    end
  end

  describe "#store_blocks" do
    it "stores each block's data" do
      image.store_blocks([[1, 0, Array.new(256, 0x5a), nil], [2, 3, Array.new(256, 0xa5), nil]])
      expect([reread.read_block(1, 0), reread.read_block(2, 3)]).to eq([Array.new(256, 0x5a), Array.new(256, 0xa5)])
    end

    it "keeps the data of a block read without any" do
      image.store_blocks([[1, 0, nil, 20]])
      expect(reread.read_block(1, 0)).to eq(Array.new(256, 0))
    end

    it "skips a block outside the image's geometry" do
      expect { image.store_blocks([[1, 21, Array.new(256, 1), nil]]) }.not_to(change { File.binread(path) })
    end

    it "keeps a disk without an error table without one" do
      image.store_blocks([[1, 0, Array.new(256, 1), 23]])
      expect(File.size(path)).to eq(174_848)
    end

    context "with an error table" do
      before do
        bytes = File.binread(path).bytes + Array.new(683, 1)
        bytes[-683] = 5 # 23, READ ERROR at 1/0
        File.binwrite(path, bytes.pack("C*"))
      end

      it "sets each block's error" do
        image.store_blocks([[1, 0, Array.new(256, 1), nil], [1, 1, nil, 22], [1, 2, Array.new(256, 1), 29]])
        expect((0..2).map { |sector| reread.block_error(1, sector) }).to eq([nil, 22, 29])
      end
    end
  end

  describe "BAM changes" do
    it "allocates a block" do
      image.allocate_block(5, 3)
      expect([reread.block_free?(5, 3), reread.read_block(18, 0)[20]]).to eq([false, 20])
    end

    it "frees a block" do
      image.allocate_block(5, 3)
      image.free_block(5, 3)
      expect([reread.block_free?(5, 3), reread.read_block(18, 0)[20]]).to eq([true, 21])
    end

    it "finds the next free block after a taken one" do
      image.allocate_block(5, 4)
      expect(image.next_free_block(5, 3)).to eq([5, 5])
    end

    it "skips the directory track looking for a free block" do
      expect(image.next_free_block(17, 20)).to eq([19, 0])
    end

    it "has no entry for tracks past 35" do
      expect(image.bam_block?(36, 0)).to be(false)
    end
  end

  describe "a host file that can't be written", :file_permissions do
    before { File.chmod(0o444, path) }

    it "isn't writable" do
      expect(image.writable?).to be(false)
    end

    it "fails as WRITE PROTECT ON" do
      expect(dos_error { image.write_file("hello", program) }).to eq(26)
    end
  end

  describe "a D81 image" do
    subject(:image) { Badline::Storage::D81Image.new(path) }

    let(:path) { File.join(dir, "blank.d81") }

    before do
      blank_d81(path)
      image.write_file("hello", program)
    end

    def reread = Badline::Storage::D81Image.new(path)

    it "writes the file" do
      expect(reread.read_file("hello")).to eq(program)
    end

    it "lays the chain out on consecutive sectors below the directory" do
      expect(reread.read_block(39, 0).first(2)).to eq([39, 1])
    end

    it "takes the blocks from the BAM at track 40, sector 1" do
      expect(reread.read_block(40, 1)[0x10 + (6 * 38)]).to eq(37)
    end

    it "uses the second BAM block above track 40" do
      image.allocate_block(41, 0)
      expect(reread.read_block(40, 2)[0x10, 2]).to eq([39, 0xfe])
    end
  end

  describe "a double-sided D71 image" do
    subject(:image) { Badline::Storage::D71Image.new(path) }

    let(:path) { File.join(dir, "blank.d71") }

    before do
      side = File.binread(blank_d64(File.join(dir, "side.d64"))).bytes
      bytes = side + Array.new(side.length, 0)
      header = d64_offset(18, 0)
      bytes[header + 3] = 0x80
      bytes[header + 0xdd] = 21 # track 36
      bytes[side.length + d64_offset(18, 0), 3] = [0xff, 0xff, 0x1f] # track 36 in 53/0
      File.binwrite(path, bytes.pack("C*"))
    end

    it "keeps the second side's free counts in the header block" do
      image.allocate_block(36, 0)
      expect(Badline::Storage::D71Image.new(path).read_block(18, 0)[0xdd]).to eq(20)
    end

    it "keeps the second side's bitmaps on track 53" do
      image.allocate_block(36, 0)
      expect(Badline::Storage::D71Image.new(path).read_block(53, 0)[0]).to eq(0xfe)
    end
  end
end
