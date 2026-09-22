# frozen_string_literal: true

require "spec_helper"

describe Badline::SID do
  subject(:sid) { described_class.new }

  let(:bus_ttl) { described_class::BUS_TTL[:mos6581] }

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

    it "replays the cycles it sat out" do
      sid[0xd400] = 0x01
      1000.times { sid.cycle! }
      sid[0xd41b]
      expect(sid.voices[0].waveform.accumulator).to eq(0x555555 + 1000)
    end

    it "lands a deferred write on the cycle it was written on" do
      1000.times { sid.cycle! }
      sid[0xd400] = 0x01
      1000.times { sid.cycle! }
      sid[0xd41b]
      expect(sid.voices[0].waveform.accumulator).to eq(0x555555 + 1000)
    end

    # SID/writedelay: a pulse at frequency $1000 and width $003 is four
    # cycles past the test bit being released by the time the CPU's read of
    # OSC3 lands, so the pulse has already gone high.
    def release_pulse_from_test(cycles)
      sid[0xd40f] = 0x10
      sid[0xd410] = 0x03
      sid[0xd412] = 0x08
      sid[0xd412] = 0x41
      cycles.times { sid.cycle! }
    end

    it "back-fills an oscillator released from the test bit" do
      release_pulse_from_test(4)
      expect(sid.osc3).to eq(0xff)
    end

    it "back-fills only the cycles that have passed" do
      release_pulse_from_test(2)
      expect(sid.osc3).to eq(0x00)
    end

    # Past the cap the oldest write is applied at the head of the replay, so
    # a frequency set on cycle 1000 runs for all 1000 of them instead.
    it "forgets the timing of a write pushed past the cap" do
      1000.times { sid.cycle! }
      sid[0xd400] = 0x01
      described_class::DEFERRED_WRITES.times { sid[0xd404] = 0x00 }
      sid[0xd41b]
      expect(sid.voices[0].waveform.accumulator).to eq(0x555555 + 1000)
    end
  end

  describe "register writes" do
    before { sid.synthesize! }

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
      (bus_ttl - 1).times { sid.cycle! }
      expect(sid[0xd400]).to eq(0x42)
    end

    it "fades to $00 once the charge drains" do
      bus_ttl.times { sid.cycle! }
      expect(sid[0xd400]).to eq(0x00)
    end

    it "recharges on a write" do
      (bus_ttl - 1).times { sid.cycle! }
      sid[0xd405] = 0x21
      (bus_ttl - 1).times { sid.cycle! }
      expect(sid[0xd400]).to eq(0x21)
    end

    it "recharges on a read of a readable register" do
      (bus_ttl - 1).times { sid.cycle! }
      sid[0xd419]
      (bus_ttl - 1).times { sid.cycle! }
      expect(sid[0xd400]).to eq(0xff)
    end

    # SID/bitfade's delayfrq0 reads $d400 every nine cycles while it waits
    # and still measures the full $1d00 on a real 6581, so the read does not
    # drain the line; reSID halves what is left of the charge, which would
    # cut the measurement to about $60.
    it "is not drained by reading a write-only register" do
      (bus_ttl - 1).times do
        sid[0xd400]
        sid.cycle!
      end
      expect(sid[0xd400]).to eq(0x42)
    end

    it "is not recharged by reading a write-only register" do
      (bus_ttl - 1).times { sid.cycle! }
      sid[0xd400]
      sid.cycle!
      expect(sid[0xd400]).to eq(0x00)
    end
  end

  # The 8580 holds the bus far longer and centres the waveform DAC; the
  # buffered oscillator top bit is pinned in the waveform spec.
  describe "the 8580" do
    subject(:sid) { described_class.new(model: :mos8580) }

    it "holds the bus latch for its own TTL" do
      sid[0xd404] = 0x42
      (described_class::BUS_TTL[:mos8580] - 1).times { sid.cycle! }
      expect(sid[0xd400]).to eq(0x42)
    end

    it "centres the waveform DAC in the mix" do
      sid.synthesize!
      sid[0xd418] = 0x0f
      sid.cycle!
      expect(sid.filter.mix).to eq(0)
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
