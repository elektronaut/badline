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

    # Only the audio needs the filter; the registers the CPU reads catch up
    # without it.
    it "stays idle through an OSC3 read" do
      sid[0xd41b]
      expect(sid).not_to be_synthesizing
    end

    it "stays idle through an ENV3 read" do
      sid[0xd41c]
      expect(sid).not_to be_synthesizing
    end

    it "starts when a sample is pulled" do
      sid.sample
      expect(sid).to be_synthesizing
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

    # A full queue catches up where it stands, so a frequency set on cycle
    # 1000 still has not run by then.
    it "keeps the timing of a write pushed past the cap" do
      1000.times { sid.cycle! }
      sid[0xd400] = 0x01
      described_class::DEFERRED_WRITES.times { sid[0xd404] = 0x00 }
      sid[0xd41b]
      expect(sid.voices[0].waveform.accumulator).to eq(0x555555)
    end
  end

  # A catch-up fast-forwards the voices a span at a time. Reading OSC3 on
  # every cycle forces one-cycle spans, so the SID read that way is the
  # reference for the one left to catch up in a single run.
  describe "batched catch-up" do
    let(:model) { :mos6581 }

    def voice_state(sid)
      sid.voices.map do |voice|
        [voice.waveform.accumulator, voice.waveform.shift_register,
         voice.waveform.osc3, voice.envelope.output, voice.envelope.state]
      end
    end

    # Writes are [reg, value] pairs, or [cycle, reg, value] to land later.
    def settle(writes, cycles)
      timed = writes.map { |write| write.length == 2 ? [0, *write] : write }
      [true, false].map do |stepped|
        chip = described_class.new(model:)
        cycles.times do |cycle|
          timed.each { |at, reg, value| chip[0xd400 + reg] = value if at == cycle }
          chip.cycle!
          chip.osc3 if stepped
        end
        voice_state(chip)
      end
    end

    def expect_batched_to_match(writes, cycles = 20_000)
      stepped, batched = settle(writes, cycles)
      expect(batched).to eq(stepped)
    end

    it "runs plain waveforms and envelopes" do
      expect_batched_to_match([[0x00, 0x37], [0x01, 0x21], [0x05, 0x4a], [0x06, 0x93], [0x04, 0x21],
                               [0x0f, 0x03], [0x0c, 0x0f], [0x0b, 0x81]])
    end

    # Pinned by SID/osc_topbit: the top bit feedback runs cycle by cycle,
    # between batched stretches on either side of it.
    it "steps a combined sawtooth feeding back its top bit" do
      expect_batched_to_match([[0x01, 0x12], [0x08, 0x40], [0x04, 0x21], [0x0b, 0x21],
                               [3000, 0x04, 0x31], [9000, 0x04, 0x21], [12_000, 0x0b, 0x71]])
    end

    # Dag Lem's LFSR reset runs through the writeback and the test bit
    # release, in the middle of a batched run.
    it "steps noise written back into the LFSR" do
      expect_batched_to_match([[0x01, 0x80], [0x04, 0x81], [0x0f, 0x21], [0x12, 0x21],
                               [4000, 0x04, 0xb8], [4001, 0x04, 0xb0], [4002, 0x04, 0x98],
                               [4003, 0x04, 0x90], [6000, 0x04, 0xc1], [9000, 0x04, 0x81]])
    end

    it "bleeds the LFSR through a held test bit" do
      expect_batched_to_match([[0x01, 0x80], [0x04, 0x81], [0x04, 0x88]], 0x9000)
    end

    it "resets a synced oscillator on the cycle the source wraps" do
      expect_batched_to_match([[0x01, 0x31], [0x08, 0x07], [0x0b, 0x23], [0x0f, 0x55], [0x12, 0x43]])
    end

    it "inverts a ring-modulated triangle" do
      expect_batched_to_match([[0x0f, 0x08], [0x12, 0x15], [0x01, 0x11], [0x04, 0x11]])
    end

    # Pinned by SID/osc3-wave0.
    it "drains the floating DAC input" do
      expect_batched_to_match([[0x04, 0x41], [0x12, 0x41], [0x12, 0x00]], 0x5000)
    end

    # The ADSR delay bug sends the rate counter the long way round.
    it "wraps a rate counter left above a lowered period" do
      expect_batched_to_match([[0x05, 0xff], [0x04, 0x01], [0x05, 0x00]], 0x9000)
    end

    it "counts off whole periods while frozen at zero" do
      expect_batched_to_match([[0x06, 0x00], [0x04, 0x01], [0x04, 0x00]], 50_000)
    end

    # Pinned by SID/detect (detect-2-new).
    context "with an 8580" do
      let(:model) { :mos8580 }

      it "reads the sawtooth a cycle late" do
        expect_batched_to_match([[0x0e, 0xff], [0x0f, 0xff], [0x12, 0x28], [0x12, 0x20]], 1003)
      end
    end
  end

  # The audio path steps the filter FILTER_CHUNK cycles at a time.
  describe "recording" do
    before { sid.record(rate: 44_100) }

    it "records one sample per window" do
      985_248.times { sid.cycle! }
      expect(sid.drain_samples.length).to eq(44_100)
    end

    it "hands each sample over once" do
      1000.times { sid.cycle! }
      sid.drain_samples
      expect(sid.drain_samples).to be_empty
    end

    it "records the silent 6581 mix settling off its DC offset" do
      sid[0xd418] = 0x0f
      50_000.times { sid.cycle! }
      expect(sid.drain_samples.last).to eq(226)
    end

    # A chunk of 1 is the exact per-cycle filter, window for window.
    context "with a filter chunk of 1" do
      subject(:sid) { described_class.new(filter_chunk: 1) }

      let(:stepped) { described_class.new }
      let(:decimator) { described_class::Decimator.new(clock_hz: Badline::TimeOfDay::CLOCK_HZ, rate: 44_100) }

      def play(chip, cycles)
        [[0x18, 0x1f], [0x17, 0xf1], [0x01, 0x20], [0x04, 0x41]].each { |reg, value| chip[0xd400 + reg] = value }
        cycles.times { yield chip.cycle! }
      end

      it "records what #sample reads cycle by cycle" do
        expected = []
        play(stepped, 5000) { expected << decimator.push(stepped.sample) }
        play(sid, 5000) { nil }
        expect(sid.drain_samples).to eq(expected.compact)
      end
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

  # One cycle per filter step, the exact path the chunked one approximates.
  describe "the mixed output" do
    subject(:sid) { described_class.new(filter_chunk: 1) }

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

    # Pinned by SID/detect (detect-2-new), which tells the chips apart by
    # this read: 3 on the 6581, 2 on the 8580.
    it "reads OSC3 a cycle behind a sawtooth started from the test bit" do
      sid.synthesize!
      [[0x0e, 0xff], [0x0f, 0xff], [0x12, 0xff], [0x12, 0x20]].each { |reg, value| sid[0xd400 + reg] = value }
      4.times { sid.cycle! }
      expect(sid[0xd41b]).to eq(0x02)
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
