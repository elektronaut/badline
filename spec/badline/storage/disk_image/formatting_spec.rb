# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../../support/blank_disk"

# The blank disks BlankDisk builds with an ID match, byte for byte, what N
# leaves on a true 2031, 8050, 8250 and 1581 in VICE.
describe Badline::Storage::DiskImage::Formatting do
  include BlankDisk

  let(:dir) { Dir.mktmpdir }
  let(:program) { Array.new(600) { |i| i & 0xff } }

  after { FileUtils.remove_entry(dir) }

  def path(name) = File.join(dir, name)

  def formatted(klass, file, id)
    klass.new(file).tap { |image| image.write_file("game", program) }.format("FRESH", id)
    File.binread(file)
  end

  {
    "D64Image" => [:blank_d64, "a.d64"], "D80Image" => [:blank_d80, "a.d80"],
    "D82Image" => [:blank_d82, "a.d82"], "D81Image" => [:blank_d81, "a.d81"]
  }.each do |class_name, (blank, file)|
    describe "#format on a #{class_name}" do
      let(:klass) { Badline::Storage.const_get(class_name) }

      before { send(blank, path(file), name: "OLD", id: "AB") }

      it "leaves the disk as a fresh one with the name and ID" do
        expected = File.binread(send(blank, path("expected"), name: "FRESH", id: "XY"))
        expect(formatted(klass, path(file), "XY".bytes)).to eq(expected)
      end

      it "without an ID keeps the disk's ID" do
        klass.new(path(file)).format("FRESH")
        expect(klass.new(path(file)).disk_id).to eq("AB".bytes)
      end

      it "without an ID empties the directory" do
        klass.new(path(file)).tap { |image| image.write_file("game", program) }.format("FRESH")
        expect(klass.new(path(file)).read_file("game")).to be_nil
      end
    end
  end

  describe "#format without an ID on a D64Image" do
    let(:image) { Badline::Storage::D64Image.new(path("a.d64")) }

    before do
      blank_d64(path("a.d64"), id: "AB")
      image.write_file("game", program)
      image.format("FRESH")
    end

    it "frees every block but the header and the directory's" do
      expect(Badline::Storage::D64Image.new(path("a.d64")).directory.blocks_free).to eq(664)
    end

    it "leaves the files' blocks as they were" do
      expect(Badline::Storage::D64Image.new(path("a.d64")).read_block(17, 0)[2, 4]).to eq([0, 1, 2, 3])
    end
  end

  describe "#format on a double-sided D71Image" do
    subject(:image) { Badline::Storage::D71Image.new(file) }

    let(:file) { path("a.d71") }

    before do
      bytes = Array.new(349_696, 0)
      bytes[d64_offset(18, 0) + 3] = 0x80
      File.binwrite(file, bytes.pack("C*"))
      image.format("FRESH", "XY".bytes)
    end

    it "formats one side, as a 1541 does" do
      expect(Badline::Storage::D71Image.new(file).directory.blocks_free).to eq(664)
    end
  end
end
