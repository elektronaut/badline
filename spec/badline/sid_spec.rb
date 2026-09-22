# frozen_string_literal: true

require "spec_helper"

describe Badline::SID do
  subject(:sid) { described_class.new }

  describe "write-only registers" do
    it "stores a write" do
      sid[0xd404] = 0x21
      expect(sid.register(0x04)).to eq(0x21)
    end

    it "reads back the last byte written to any register" do
      sid[0xd404] = 0x21
      expect(sid[0xd400]).to eq(0x21)
    end

    it "reads $00 before anything has been written" do
      expect(sid[0xd400]).to eq(0x00)
    end

    it "does not read the register that was written" do
      sid[0xd400] = 0x11
      sid[0xd404] = 0x21
      expect(sid[0xd400]).to eq(0x21)
    end

    it "keeps the volume register write-only" do
      sid[0xd418] = 0x0f
      expect(sid.register(0x18)).to eq(0x0f)
    end
  end

  describe "voice 3 readback" do
    # Voice 3 lives at $d40e-$d414: control at $d412, ADSR above it.
    def gate_voice3(control)
      sid[0xd413] = 0x00
      sid[0xd412] = control
    end

    it "ignores a write to OSC3" do
      sid[0xd41b] = 0x42
      expect(sid.osc3).to eq(0x00)
    end

    it "ignores a write to ENV3" do
      sid[0xd41c] = 0x42
      expect(sid.env3).to eq(0x00)
    end

    it "reads $00 from OSC3 with no waveform selected" do
      expect(sid[0xd41b]).to eq(0x00)
    end

    it "reads the top eight bits of the voice 3 oscillator" do
      gate_voice3(0x21)
      expect(sid[0xd41b]).to eq(0x55)
    end

    it "reads the voice 3 envelope" do
      gate_voice3(0x21)
      sid.synthesize!
      (9 * 3).times { sid.cycle! }
      expect(sid[0xd41c]).to eq(0x03)
    end

    # SID/ringmod: a stopped, ring-modulated triangle inverts to full scale.
    it "inverts a ring-modulated triangle against a stopped voice 2" do
      sid[0xd40b] = 0x08
      gate_voice3(0x08)
      gate_voice3(0x15)
      expect(sid[0xd41b]).to eq(0xff)
    end

    it "leaves the bus holding the value that was read" do
      gate_voice3(0x21)
      sid[0xd41b]
      expect(sid[0xd400]).to eq(0x55)
    end
  end

  describe "the synthesis clock" do
    it "idles until something asks for the chip's state" do
      expect(sid).not_to be_synthesizing
    end

    it "starts on an OSC3 read" do
      sid[0xd41b]
      expect(sid).to be_synthesizing
    end

    it "starts on an ENV3 read" do
      sid[0xd41c]
      expect(sid).to be_synthesizing
    end

    it "starts when a sample is pulled" do
      sid.sample
      expect(sid).to be_synthesizing
    end

    it "leaves the oscillators alone while it idles" do
      sid[0xd400] = 0xff
      1000.times { sid.cycle! }
      expect(sid.voices[0].waveform.accumulator).to eq(0x555555)
    end

    it "runs the oscillators once started" do
      sid[0xd400] = 0xff
      sid[0xd41b]
      1000.times { sid.cycle! }
      expect(sid.voices[0].waveform.accumulator).not_to eq(0x555555)
    end
  end

  describe "register writes" do
    it "reaches the voice oscillators" do
      sid[0xd407] = 0x34
      sid[0xd408] = 0x12
      expect(sid.voices[1].waveform.frequency).to eq(0x1234)
    end

    it "reaches the voice envelopes" do
      sid[0xd414] = 0x80
      sid[0xd412] = 0x11
      expect(sid.voices[2].envelope.state).to eq(:attack)
    end

    it "reaches the filter" do
      sid[0xd418] = 0x1f
      expect(sid.filter.volume).to eq(0x0f)
    end
  end

  describe "the mixed output" do
    before do
      sid.synthesize!
      sid[0xd418] = 0x0f
      sid.cycle!
    end

    it "sits on the 6581 DC offset while the voices are silent" do
      expect(sid.filter.mix).to eq(176_790)
    end

    # The RC network on the board strips that offset back off, down to the
    # residual its high-pass integrator stalls on.
    it "drains the DC offset off the output" do
      50_000.times { sid.cycle! }
      expect(sid.output).to eq(9986)
    end

    it "scales the mix into a signed 16-bit sample" do
      100.times { sid.cycle! }
      expect(sid.sample).to eq(15_931)
    end

    it "is silent at volume zero" do
      sid[0xd418] = 0x00
      1000.times { sid.cycle! }
      expect(sid.output).to eq(0)
    end

    it "swings the mix with an open voice" do
      sid[0xd406] = 0xf0
      sid[0xd401] = 0x1d
      sid[0xd404] = 0x21
      5000.times { sid.cycle! }
      expect(sid.sample).to be > 12_000
    end
  end

  describe "the data bus latch" do
    before { sid[0xd404] = 0x42 }

    it "holds the last value while the charge lasts" do
      (Badline::SID::BUS_TTL - 1).times { sid.cycle! }
      expect(sid[0xd400]).to eq(0x42)
    end

    it "fades to $00 once the charge drains" do
      Badline::SID::BUS_TTL.times { sid.cycle! }
      expect(sid[0xd400]).to eq(0x00)
    end

    it "recharges on a write" do
      (Badline::SID::BUS_TTL - 1).times { sid.cycle! }
      sid[0xd405] = 0x21
      (Badline::SID::BUS_TTL - 1).times { sid.cycle! }
      expect(sid[0xd400]).to eq(0x21)
    end

    it "recharges on a read of a readable register" do
      (Badline::SID::BUS_TTL - 1).times { sid.cycle! }
      sid[0xd419]
      (Badline::SID::BUS_TTL - 1).times { sid.cycle! }
      expect(sid[0xd400]).to eq(0xff)
    end

    it "is not recharged by reading a write-only register" do
      (Badline::SID::BUS_TTL - 1).times { sid.cycle! }
      sid[0xd400]
      sid.cycle!
      expect(sid[0xd400]).to eq(0x00)
    end
  end

  describe "paddle inputs" do
    let(:pots) { Struct.new(:pot_x, :pot_y).new(0x40, 0x80) }

    it "floats POTX high with no source attached" do
      expect(sid[0xd419]).to eq(0xff)
    end

    it "floats POTY high with no source attached" do
      expect(sid[0xd41a]).to eq(0xff)
    end

    it "reads POTX from an injected source" do
      expect(described_class.new(pots:)[0xd419]).to eq(0x40)
    end

    it "reads POTY from an injected source" do
      expect(described_class.new(pots:)[0xd41a]).to eq(0x80)
    end

    it "takes a source attached after construction" do
      sid.pots = pots
      expect(sid[0xd419]).to eq(0x40)
    end

    it "ignores a write to POTX" do
      sid[0xd419] = 0x00
      expect(sid[0xd419]).to eq(0xff)
    end
  end

  # $d41d-$d41f are not wired to anything inside the chip, so they behave
  # like the write-only range.
  describe "unconnected registers" do
    it "reads the bus latch" do
      sid[0xd400] = 0x42
      expect(sid[0xd41d]).to eq(0x42)
    end

    it "reads $00 before anything has been written" do
      expect(sid[0xd41f]).to eq(0x00)
    end
  end

  describe "mirroring" do
    it "writes through a mirror" do
      sid[0xd7e4] = 0x21
      expect(sid.register(0x04)).to eq(0x21)
    end

    it "reads POTX through a mirror" do
      expect(sid[0xd7f9]).to eq(0xff)
    end

    it "reads the unconnected registers through a mirror" do
      sid[0xd400] = 0x42
      expect(sid[0xd43f]).to eq(0x42)
    end
  end
end
