# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "zlib"

# The fixtures are VICE 3.10's c1541 run on zero-filled images of each
# size, gzipped: `format "test disk,ab"` for the blank ones, and for the
# D9090 with files `format "hard disk,hd"`, then `write` of a 1,002-byte
# PRG as "hello" and of 40 "LINE n OF THE TEXT" lines as "text,s".
describe Badline::Storage::D90Image do
  let(:dir) { Dir.mktmpdir }

  after { FileUtils.remove_entry(dir) }

  def fixture(name) = Zlib::GzipReader.open(File.expand_path("../../fixtures/#{name}.d90.gz", __dir__), &:read).b

  def image_from(name, **)
    path = File.join(dir, "#{name}.d90")
    File.binwrite(path, fixture(name))
    described_class.new(path, **)
  end

  def text = (1..40).map { |line| "LINE #{line} OF THE TEXT\r" }.join.bytes

  describe ".heads_for" do
    it "gives a D9060's image four heads and a D9090's six" do
      expect([5_013_504, 7_520_256, 1_000].map { |size| described_class.heads_for(size) }).to eq([4, 6, nil])
    end
  end

  describe "the geometry" do
    it "numbers a D9090's sectors across its six heads" do
      image = image_from("c1541-blank-9090")
      expect([image.sectors_in(0), image.block_count, image.lba(1, 191)]).to eq([192, 29_376, 383])
    end

    it "takes the heads it's given over its size" do
      image = image_from("c1541-blank-9090", heads: 4)
      expect([image.block_count, image.read_blocks(19_583, 1)&.length]).to eq([19_584, 256])
    end

    it "reads an empty file as a blank disk of the heads it's given" do
      File.binwrite(File.join(dir, "empty.d90"), "")
      image = described_class.new(File.join(dir, "empty.d90"), heads: 6)
      expect(image.read_blocks(29_375, 1)).to eq(Array.new(256, 0))
    end
  end

  describe "#format" do
    def formatted(size)
      path = File.join(dir, "new.d90")
      File.binwrite(path, "\x55".b * size)
      described_class.new(path).format("TEST DISK", "AB".bytes)
      File.binread(path)
    end

    it "lays out a D9060 as c1541 does, every other block cleared" do
      expect(formatted(5_013_504)).to eq(fixture("c1541-blank-9060"))
    end

    it "lays out a D9090 as c1541 does, every other block cleared" do
      expect(formatted(7_520_256)).to eq(fixture("c1541-blank-9090"))
    end
  end

  describe "#directory" do
    it "counts a blank D9060's free blocks off every cylinder but the directory's, as xpet lists them" do
      expect(image_from("c1541-blank-9060").directory.blocks_free).to eq(19_441)
    end

    it "counts a blank D9090's free blocks as xpet lists them" do
      expect(image_from("c1541-blank-9090").directory.blocks_free).to eq(29_162)
    end

    context "with files" do
      subject(:listing) { image_from("c1541-files-9090").directory }

      it "reads the name and ID from the header at 76/20" do
        expect([listing.name, listing.id])
          .to eq(["HARD DISK".bytes + ([0xa0] * 7), "HD".bytes + [0xa0, 0x33, 0x41]])
      end

      it "lists each file with its type and blocks" do
        expect(listing.entries.map { |entry| [entry.name.first(5), entry.type, entry.blocks] })
          .to eq([["HELLO".bytes, 2, 4], ["TEXT".bytes + [0xa0], 1, 4]])
      end

      it "counts the free blocks c1541 lists" do
        expect(listing.blocks_free).to eq(29_154)
      end
    end
  end

  describe "#read_file" do
    subject(:image) { image_from("c1541-files-9090") }

    it "reads a PRG's chain across a head's sectors" do
      expect(image.read_file("hello")).to eq([0x01, 0x04] + Array.new(1000) { |i| (i * 7) & 0xff })
    end

    it "reads a SEQ file by its type" do
      expect(image.read_file("text", type: :seq)).to eq(text)
    end
  end

  describe "#read_block" do
    subject(:image) { image_from("c1541-blank-9060") }

    it "reads the block 0/0 points from" do
      expect(image.read_block(0, 0).first(12)).to eq([0, 1, 0, 0xff, 76, 10, 76, 20, 1, 0, 0x41, 0x42])
    end

    it "has no sector past the last head's" do
      expect([image.read_block(152, 127)&.length, image.read_block(152, 128), image.read_block(153, 0)])
        .to eq([256, nil, nil])
    end
  end

  describe "#block_free?" do
    subject(:image) { image_from("c1541-blank-9060") }

    it "keeps the directory and header in use on head 0 of cylinder 76" do
      expect([10, 11, 20, 42].map { |sector| image.block_free?(76, sector) }).to eq([false, true, false, true])
    end

    it "keeps the BAM block of cylinders 12 to 23 in use at 13/0" do
      expect([image.block_free?(13, 0), image.block_free?(12, 0)]).to eq([false, true])
    end
  end

  describe "#allocate_block" do
    subject(:image) { image_from("c1541-blank-9090") }

    it "takes the block from its head's count" do
      image.allocate_block(40, 100)
      expect(described_class.new(image.path).directory.blocks_free).to eq(29_161)
    end
  end

  describe "#write_blocks" do
    subject(:image) { image_from("c1541-blank-9060") }

    let(:data) { Array.new(512) { |i| i & 0xff } }

    it "writes the blocks into the host file at the LBA" do
      image.write_blocks(1000, data)
      expect(File.binread(image.path, 512, 1000 * 256).bytes).to eq(data)
    end

    it "reads them back" do
      image.write_blocks(1000, data)
      expect(image.read_blocks(1000, 2)).to eq(data)
    end

    it "writes nothing past the disk's end" do
      image.write_blocks(19_583, data)
      expect(File.binread(image.path)).to eq(fixture("c1541-blank-9060"))
    end

    it "raises WRITE PROTECT ON on a read-only disk" do
      read_only = described_class.new(image.path, read_only: true)
      expect { read_only.write_blocks(0, data) }
        .to raise_error(an_instance_of(Badline::Storage::WriteError).and(having_attributes(code: 26)))
    end
  end

  describe "#write_file" do
    subject(:image) { image_from("c1541-blank-9090") }

    before { image.write_file("game", Array.new(600) { |i| i & 0xff }) }

    it "reads the file back" do
      expect(described_class.new(image.path).read_file("game")).to eq(Array.new(600) { |i| i & 0xff })
    end

    it "takes its three blocks from the free count" do
      expect(described_class.new(image.path).directory.blocks_free).to eq(29_159)
    end
  end
end
