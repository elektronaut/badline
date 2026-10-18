# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../../support/blank_disk"

# The status each command reports is what a true 2031 and 8050 report in
# VICE for the same command.
describe Badline::KernalTrap::DOS::DiskCommands do
  include BlankDisk

  subject(:drive) { Badline::KernalTrap::DOS.new(Badline::Storage::D64Image.new(path)) }

  let(:dir) { Dir.mktmpdir }
  let(:path) { blank_d64(File.join(dir, "blank.d64"), id: "AB") }

  before do
    status
    write_file(2, "first,p,w", [1, 2])
    write_file(2, "second,p,w", [3])
    write_file(2, "data,s,w", [4, 5])
  end

  after { FileUtils.remove_entry(dir) }

  def status
    bytes = []
    loop do
      byte, eoi = drive.read(15)
      bytes << byte
      break if eoi
    end
    bytes.pack("C*").chomp("\r")
  end

  def command(text) = drive.write(15, "#{text}\r".bytes)

  def reported(text)
    command(text)
    status
  end

  # The image as the host file now holds it
  def disk = Badline::Storage::D64Image.new(path)

  def write_file(secondary, name, bytes)
    drive.open(secondary, name)
    drive.write(secondary, bytes)
    drive.close(secondary)
  end

  describe "N with an ID" do
    before { command("N0:FRESH,XY") }

    it "reports OK" do
      expect(status).to eq("00, OK,00,00")
    end

    it "formats the disk" do
      expect(File.binread(path)).to eq(File.binread(blank_d64(File.join(dir, "fresh.d64"), name: "FRESH", id: "XY")))
    end
  end

  describe "N without an ID" do
    before { command("N:FRESH") }

    it "keeps the disk's ID" do
      expect(disk.disk_id).to eq("AB".bytes)
    end

    it "empties the directory" do
      expect(disk.read_file("first")).to be_nil
    end
  end

  it "takes the carriage return after a one-character ID into it" do
    command("N0:FRESH,X")
    expect(disk.disk_id).to eq([0x58, 0x0d])
  end

  it "only clears the disk for a comma with nothing after it" do
    command("N0:FRESH,")
    expect(disk.disk_id).to eq("AB".bytes)
  end

  it "reports a SYNTAX ERROR (34) for N without a colon" do
    expect(reported("N")).to eq("34,SYNTAX ERROR,00,00")
  end

  it "reports a SYNTAX ERROR for a disk name with a wildcard" do
    expect(reported("N0:FR*,XY")).to eq("30,SYNTAX ERROR,00,00")
  end

  describe "R" do
    before { command("R0:RENAMED=FIRST") }

    it "reports OK" do
      expect(status).to eq("00, OK,00,00")
    end

    it "gives the file its new name" do
      expect(disk.read_file("renamed")).to eq([1, 2])
    end

    it "leaves no file under the old name" do
      expect(disk.read_file("first")).to be_nil
    end
  end

  describe "what R reports" do
    {
      "R0:THIRD=0:SECOND" => "00, OK,00,00",
      "R0:X=MISSING" => "62,FILE NOT FOUND,00,00",
      "R0:SECOND=DATA" => "63,FILE EXISTS,00,00",
      "R0:DATA=MISSING" => "62,FILE NOT FOUND,00,00",
      "R0:X=1:SECOND" => "62,FILE NOT FOUND,00,00",
      "R0:X*=SECOND" => "30,SYNTAX ERROR,00,00",
      "R0:X=SEC*" => "30,SYNTAX ERROR,00,00",
      "R0:X=SECOND,P" => "30,SYNTAX ERROR,00,00",
      "R0:SECOND" => "30,SYNTAX ERROR,00,00",
      "RX=SECOND" => "34,SYNTAX ERROR,00,00"
    }.each do |text, report|
      it "reports #{report} for #{text}" do
        expect(reported(text)).to eq(report)
      end
    end
  end

  describe "C" do
    before { command("C0:JOINED=SECOND,DATA,FIRST") }

    it "reports OK" do
      expect(status).to eq("00, OK,00,00")
    end

    it "writes the files one after another" do
      expect(disk.read_file("joined")).to eq([3, 4, 5, 1, 2])
    end

    it "writes them as the type of the first" do
      expect(disk.read_file("joined", type: :seq)).to be_nil
    end
  end

  describe "C onto the first file named with drive 0" do
    before { command("C0:DATA=0:DATA,0:SECOND") }

    it "adds the others to its end" do
      expect(disk.read_file("data", type: :seq)).to eq([4, 5, 3])
    end
  end

  describe "what C reports" do
    {
      "C0:SECOND=MISSING" => "62,FILE NOT FOUND,00,00",
      "C0:SECOND=DATA" => "63,FILE EXISTS,00,00",
      "C0:DATA=DATA,SECOND" => "63,FILE EXISTS,00,00",
      "C0:SECOND=0:SECOND,0:DATA" => "64,FILE TYPE MISMATCH,00,00",
      "C0:X=" => "62,FILE NOT FOUND,00,00",
      "C0:X=FIRST," => "62,FILE NOT FOUND,00,00",
      "C0:X=1:FIRST" => "62,FILE NOT FOUND,00,00",
      "C0:X=FI*" => "30,SYNTAX ERROR,00,00",
      "C1=0" => "31,SYNTAX ERROR,00,00",
      "D1=0" => "31,SYNTAX ERROR,00,00"
    }.each do |text, report|
      it "reports #{report} for #{text}" do
        expect(reported(text)).to eq(report)
      end
    end
  end

  describe "on a write-protected disk" do
    subject(:drive) { Badline::KernalTrap::DOS.new(Badline::Storage::D64Image.new(path, read_only: true)) }

    let(:path) do
      blank_d64(File.join(dir, "protected.d64")).tap { |file| Badline::Storage::D64Image.new(file).write_file("first", [1]) }
    end

    it "fails N as WRITE PROTECT ON" do
      expect(reported("N0:FRESH,XY")).to eq("26,WRITE PROTECT ON,00,00")
    end

    it "fails R as WRITE PROTECT ON" do
      expect(reported("R0:X=FIRST")).to eq("26,WRITE PROTECT ON,00,00")
    end
  end

  describe "on a host directory" do
    subject(:drive) { Badline::KernalTrap::DOS.new(Badline::Storage::HostDirectory.new(dir)) }

    it "fails C as WRITE PROTECT ON" do
      expect(reported("C0:X=FIRST")).to eq("26,WRITE PROTECT ON,00,00")
    end
  end
end
