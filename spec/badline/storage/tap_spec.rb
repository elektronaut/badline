# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

describe Badline::Storage::TAP do
  subject(:tape) { described_class.new(path) }

  let(:dir) { Dir.mktmpdir }
  let(:path) { File.join(dir, "tape.tap") }
  let(:version) { 1 }
  let(:platform) { 0 }
  let(:data) { [0x30, 0x42, 0x56] }

  before { write_tape(data) }

  after { FileUtils.remove_entry(dir) }

  def write_tape(bytes, size: bytes.length, signature: "C64-TAPE-RAW")
    header = signature.bytes + [version, platform, 0, 0] + [size].pack("V").bytes
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

    context "with a version 2 tape" do
      let(:version) { 2 }
      let(:platform) { 2 }
      let(:data) { [0x1a, 0x1b, 0x35, 0x00, 0x34, 0x12, 0x00, 0x6a] }

      before { write_tape(data, signature: "C16-TAPE-RAW") }

      it "reads a pulse from each two half waves" do
        expect(pulses).to eq([(0x1a + 0x1b) * 8, (0x35 * 8) + 0x1234, 0x6a * 8])
      end

      it "reads a half wave left at the end as the whole of a pulse" do
        2.times { tape.next_pulse }
        expect(tape.next_pulse).to eq(0x6a * 8)
      end

      it "reads the half waves one at a time" do
        half_waves = Array.new(5) { tape.next_half_wave }
        expect(half_waves).to eq([0x1a * 8, 0x1b * 8, 0x35 * 8, 0x1234, 0x6a * 8])
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

    it "reads the platform" do
      expect(tape.platform).to eq(0)
    end

    context "with a C16 tape" do
      let(:version) { 2 }
      let(:platform) { 2 }

      before { write_tape(data, signature: "C16-TAPE-RAW") }

      it "reads the version and the platform" do
        expect([tape.version, tape.platform]).to eq([2, 2])
      end
    end

    context "with a VIC-20 tape" do
      let(:platform) { 1 }

      it "reads the VIC-20 platform" do
        expect(tape.platform).to eq(1)
      end
    end

    it "rejects a file without the signature" do
      File.binwrite(path, "NOTATAPE" * 8)
      expect { tape }.to raise_error(described_class::FormatError, /signature/)
    end

    it "rejects a version it cannot play" do
      write_tape(data)
      File.binwrite(path, File.binread(path).tap { |raw| raw.setbyte(0x0c, 3) })
      expect { tape }.to raise_error(described_class::FormatError, /version 3/)
    end
  end

  describe ".create" do
    subject(:blank) { described_class.create(File.join(dir, "blank.tap"), platform: 1) }

    it "writes a version 1 tape for the platform, with no pulses" do
      expect([blank.version, blank.platform, File.size(blank.path), blank.end?]).to eq([1, 1, 20, true])
    end

    it "writes a version 1 tape for the PET" do
      pet = described_class.create(File.join(dir, "pet.tap"), platform: described_class::PET_PLATFORM)
      expect([File.binread(pet.path, 12), pet.version, pet.platform]).to eq(["C64-TAPE-RAW", 1, 3])
    end

    it "writes a version 2 C16 tape for the 264 series" do
      c16 = described_class.create(File.join(dir, "c16.tap"), platform: 2)
      expect([File.binread(c16.path, 12), c16.version, c16.platform]).to eq(["C16-TAPE-RAW", 2, 2])
    end
  end

  describe ".platform_of" do
    let(:platform) { described_class::PET_PLATFORM }

    it "reads a PET tape's platform from its header" do
      expect(described_class.platform_of(path)).to eq(3)
    end

    it "finds no platform in a file that isn't a tape" do
      File.binwrite(path, "\x01\x04")
      expect(described_class.platform_of(path)).to be_nil
    end
  end

  describe "#record_pulse" do
    before { tape.next_pulse }

    it "records a short pulse as a byte of units of 8 cycles, in place of the rest of the tape" do
      tape.record_pulse(363)
      expect(tape.bytes.drop(20)).to eq([0x30, 0x2d])
    end

    it "records a long pulse as a zero and its cycle count on a version 1 tape" do
      tape.record_pulse(0x12345)
      expect(tape.bytes.drop(21)).to eq([0x00, 0x45, 0x23, 0x01])
    end

    it "leaves the tape at its end" do
      tape.record_pulse(363)
      expect(tape.end?).to be(true)
    end

    context "with a version 2 tape" do
      let(:version) { 2 }

      it "records a pulse as two half waves" do
        tape.record_pulse(363)
        expect(tape.bytes.drop(20)).to eq([0x30, 0x42, 0x17, 0x17])
      end

      it "records a half wave as one byte" do
        tape.record_half_wave(212)
        expect(tape.bytes.drop(20)).to eq([0x30, 0x42, 0x1b])
      end
    end

    context "with a version 0 tape" do
      let(:version) { 0 }

      it "records a long pulse as an overflow" do
        tape.record_pulse(0x12345)
        expect(tape.bytes.drop(21)).to eq([0x00])
      end
    end
  end

  describe "#save" do
    before do
      tape.next_pulse
      tape.record_pulse(363)
      tape.record_pulse(363)
      tape.save
    end

    it "writes the tape back with the data size it holds" do
      expect(File.binread(path).bytes.drop(16)).to eq([3, 0, 0, 0, 0x30, 0x2d, 0x2d])
    end
  end
end
