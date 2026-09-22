# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

describe Badline::Storage::TAP do
  subject(:tape) { described_class.new(path) }

  let(:dir) { Dir.mktmpdir }
  let(:path) { File.join(dir, "tape.tap") }
  let(:version) { 1 }
  let(:data) { [0x30, 0x42, 0x56] }

  before { write_tape(data) }

  after { FileUtils.remove_entry(dir) }

  def write_tape(bytes, size: bytes.length)
    header = "C64-TAPE-RAW".bytes + [version, 0, 0, 0] + [size].pack("V").bytes
    File.binwrite(path, (header + bytes).pack("C*"))
  end

  def pulses
    list = []
    while (pulse = tape.next_pulse)
      list << pulse
    end
    list
  end

  describe "#next_pulse" do
    it "scales each byte by eight cycles" do
      expect(pulses).to eq([0x30 * 8, 0x42 * 8, 0x56 * 8])
    end

    it "returns nil past the end of the tape" do
      pulses
      expect(tape.next_pulse).to be_nil
    end

    context "with a version 1 long pulse" do
      let(:data) { [0x00, 0x34, 0x12, 0x01, 0x30] }

      it "reads the escape as a 24-bit cycle count" do
        expect(pulses).to eq([0x011234, 0x30 * 8])
      end
    end

    context "with a version 0 overflow" do
      let(:version) { 0 }
      let(:data) { [0x00, 0x30] }

      it "reads the escape as a long pulse" do
        expect(pulses).to eq([described_class::OVERFLOW, 0x30 * 8])
      end
    end

    context "when the stated size stops short of the file" do
      before { write_tape(data, size: 2) }

      it "ends the tape at the stated size" do
        expect(pulses.length).to eq(2)
      end
    end

    context "when the stated size runs past the file" do
      before { write_tape(data, size: 0x1000) }

      it "ends the tape at the end of the file" do
        expect(pulses.length).to eq(3)
      end
    end

    context "when the stated size is zeroed" do
      before { write_tape(data, size: 0) }

      it "plays the whole file" do
        expect(pulses.length).to eq(3)
      end
    end
  end

  describe "#rewind" do
    it "plays the tape again from the start" do
      pulses
      tape.rewind
      expect(pulses).to eq([0x30 * 8, 0x42 * 8, 0x56 * 8])
    end
  end

  describe "#end?" do
    it "is false with pulses left" do
      expect(tape).not_to be_end
    end

    it "is true once the pulses run out" do
      pulses
      expect(tape).to be_end
    end
  end

  describe ".new" do
    it "reads the version" do
      expect(tape.version).to eq(1)
    end

    it "rejects a file without the signature" do
      File.binwrite(path, "NOTATAPE" * 8)
      expect { tape }.to raise_error(described_class::FormatError, /signature/)
    end

    it "rejects a version it cannot play" do
      write_tape(data)
      File.binwrite(path, File.binread(path).tap { |raw| raw.setbyte(0x0c, 2) })
      expect { tape }.to raise_error(described_class::FormatError, /version 2/)
    end
  end
end
