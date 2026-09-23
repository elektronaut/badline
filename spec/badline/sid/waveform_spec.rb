# frozen_string_literal: true

require "spec_helper"

describe Badline::SID::Waveform do
  subject(:waveform) { described_class.new }

  # Control register: waveform in the high nibble, test ($08), ring ($04)
  # and sync ($02) in the low one.
  def start(control, frequency: 0x0000)
    waveform.frequency_low = frequency & 0xff
    waveform.frequency_high = frequency >> 8
    waveform.control = control
  end

  # Zeroes the accumulator through the test bit before running.
  def restart(control, frequency:, cycles: 0)
    waveform.control = 0x08
    start(control, frequency:)
    cycles.times { waveform.cycle! }
  end

  describe "phase accumulator" do
    it "powers on with the odd bits inverted" do
      expect(waveform.accumulator).to eq(0x555555)
    end

    it "advances by the frequency every cycle" do
      restart(0x20, frequency: 0x1234, cycles: 3)
      expect(waveform.accumulator).to eq(0x369c)
    end

    it "wraps after a full period" do
      restart(0x20, frequency: 0x8000, cycles: 512)
      expect(waveform.accumulator).to eq(0x000000)
    end

    it "stays put while the test bit is held" do
      start(0x28, frequency: 0xffff)
      10.times { waveform.cycle! }
      expect(waveform.accumulator).to eq(0x000000)
    end

    it "keeps the frequency low byte when the high byte is written" do
      waveform.frequency_low = 0x34
      waveform.frequency_high = 0x12
      expect(waveform.frequency).to eq(0x1234)
    end
  end

  describe "sawtooth" do
    it "takes the top 12 bits of the accumulator" do
      expect(waveform.sawtooth).to eq(0x555)
    end

    it "rises with the phase" do
      restart(0x20, frequency: 0x8000, cycles: 256)
      expect(waveform.sawtooth).to eq(0x800)
    end
  end

  describe "triangle" do
    it "doubles the ramp over the lower half of the phase" do
      expect(waveform.triangle).to eq(0xaaa)
    end

    it "folds the ramp back down once the MSB is set" do
      restart(0x10, frequency: 0x8000, cycles: 256)
      expect(waveform.triangle).to eq(0xfff)
    end
  end

  describe "ring modulation" do
    let(:source) { described_class.new }

    before do
      waveform.sync_source = source
      source.control = 0x08
    end

    def raise_source_msb
      source.frequency_high = 0x80
      source.control = 0x00
      256.times { source.cycle! }
    end

    # SID/ringmod: two stopped oscillators, triangle + ring on the second.
    it "inverts the ramp while the modulating MSB is clear" do
      restart(0x14, frequency: 0x0000)
      expect(waveform.triangle).to eq(0xfff)
    end

    it "leaves the ramp alone while the modulating MSB is set" do
      raise_source_msb
      restart(0x14, frequency: 0x0000)
      expect(waveform.triangle).to eq(0x000)
    end

    it "does not affect a combined sawtooth" do
      restart(0x34, frequency: 0x0000)
      expect(waveform.triangle).to eq(0x000)
    end
  end

  describe "pulse" do
    it "reads low below the pulse width" do
      waveform.pulse_width_low = 0xff
      waveform.pulse_width_high = 0x0f
      expect(waveform.pulse).to eq(0x000)
    end

    it "reads high from the pulse width up" do
      waveform.pulse_width_low = 0x00
      waveform.pulse_width_high = 0x00
      expect(waveform.pulse).to eq(0xfff)
    end

    it "masks the pulse width to 12 bits" do
      waveform.pulse_width_high = 0xff
      expect(waveform.pulse_width).to eq(0xf00)
    end

    it "reads high while the test bit is held" do
      waveform.pulse_width_low = 0xff
      waveform.pulse_width_high = 0x0f
      waveform.control = 0x48
      expect(waveform.pulse).to eq(0xfff)
    end
  end

  describe "noise" do
    it "gathers eight taps off the seeded LFSR" do
      expect(waveform.noise).to eq(0xfe0)
    end

    # Pinned by SID/noisewriteback (test2): bit 19 rises on cycle 16, the
    # first phase of the shift latches the register on 17 and the second
    # shifts it on 18.
    it "holds its state until two cycles after accumulator bit 19 rises" do
      restart(0x80, frequency: 0x8000, cycles: 17)
      expect(waveform.shift_register).to eq(0x7ffffc)
    end

    it "shifts left two cycles after bit 19 rises, feeding back bits 22 and 17" do
      restart(0x80, frequency: 0x8000, cycles: 18)
      expect(waveform.shift_register).to eq(0x7ffff8)
    end

    it "shifts once for each rise of accumulator bit 19" do
      restart(0x80, frequency: 0x8000, cycles: 50)
      expect(waveform.noise).to eq(0xfc0)
    end

    it "stalls the LFSR while the test bit is held" do
      waveform.control = 0x88
      10.times { waveform.cycle! }
      expect(waveform.shift_register).to eq(described_class::NOISE_SEED)
    end

    # SID/wf12nsr reads $ff off a register the test bit has held for a while.
    it "bleeds every bit high once the test bit has held long enough" do
      waveform.control = 0x88
      described_class::SHIFT_REGISTER_RESET_DELAY.times { waveform.cycle! }
      expect(waveform.noise).to eq(0xff0)
    end

    # Bit 22 is forced high while the test bit is set, so the bit clocked in
    # on release is the complement of bit 17.
    it "shifts a bit in over the forced bit 22 when the test bit is released" do
      waveform.control = 0x88
      waveform.control = 0x80
      expect(waveform.shift_register).to eq(0x7ffffc)
    end
  end

  # Dag Lem's fast LFSR reset (SID/noise-reset_new) drives the register from
  # both directions: combined waveforms clear bits, the test bit shifts them.
  describe "combined waveform writeback" do
    def toggle_test(control, times)
      times.times do
        waveform.control = control | 0x08
        6.times { waveform.cycle! }
        waveform.control = control
        6.times { waveform.cycle! }
      end
    end

    it "clears every LFSR bit through three noise+sawtooth+triangle shifts" do
      toggle_test(0xb0, 3)
      expect(waveform.shift_register).to eq(0x000000)
    end

    it "sets bits 0 to 17 by toggling the test bit over plain noise" do
      toggle_test(0xb0, 3)
      toggle_test(0x80, 18)
      expect(waveform.shift_register).to eq(0x03ffff)
    end

    # Pinned by SID/noisewriteback (test2): the triangle holds a bled
    # register's taps low until the shift two cycles after the bit 19 rise
    # fills them from the bits below, and OSC3 catches that one output.
    describe "around a shift" do
      def shift_under_triangle(model, cycles)
        chip = described_class.new(model:)
        chip.control = 0x08
        described_class::SHIFT_REGISTER_RESET_DELAY.times { chip.cycle! }
        chip.control = 0x90
        chip.cycle!
        chip.frequency_low = chip.frequency_high = 0xff
        cycles.times { chip.cycle! }
        chip.osc3 >> 4
      end

      it "reads the triangle through the shifted-in bits on the 6581" do
        expect(shift_under_triangle(:mos6581, 11)).to eq(0x14)
      end

      it "reads the delayed triangle through them on the 8580" do
        expect(shift_under_triangle(:mos8580, 11)).to eq(0x12)
      end

      it "reads the taps still pulled low the cycle before" do
        expect(shift_under_triangle(:mos6581, 10)).to eq(0x00)
      end
    end

    it "leaves the LFSR alone when noise is the only waveform selected" do
      restart(0x80, frequency: 0x0000, cycles: 8)
      expect(waveform.shift_register).to eq(0x7ffffc)
    end

    # Pinned by SID/wb_testsuite and SID/noisewriteback (test1): whether the
    # test bit's release writes the old waveform back depends on the change.
    # From the power-on LFSR a writeback reads $576bb4 after the shift, a
    # plain shift $7ffffc.
    describe "as the test bit falls" do
      def release(from, to, model: :mos6581)
        chip = described_class.new(model:)
        chip.control = (from << 4) | 0x08
        chip.control = to << 4
        chip.shift_register
      end

      it "writes back while noise stays combined" do
        expect(release(0x9, 0x9)).to eq(0x576bb4)
      end

      it "writes nothing back dropping to noise alone" do
        expect(release(0x9, 0x8)).to eq(0x7ffffc)
      end

      it "writes back dropping to noise alone from all four waveforms" do
        expect(release(0xf, 0x8)).to eq(0x576bb4)
      end

      it "writes nothing back into pulse+noise" do
        expect(release(0x9, 0xc)).to eq(0x7ffffc)
      end

      it "writes nothing back trading triangle for sawtooth on the 6581" do
        expect(release(0x9, 0xa)).to eq(0x7ffffc)
      end

      it "writes back trading triangle for sawtooth on the 8580" do
        expect(release(0x9, 0xa, model: :mos8580)).to eq(0x576bb4)
      end
    end
  end

  # SID/osc_topbit: on the 6581 the sawtooth switch wires the accumulator MSB
  # straight to the output line, so a combined waveform can pull it down.
  describe "top bit feedback" do
    it "clears the accumulator MSB when a combined sawtooth reads low" do
      restart(0x30, frequency: 0x8000, cycles: 256)
      waveform.cycle!
      expect(waveform.accumulator).to eq(0x008000)
    end

    it "leaves the accumulator alone when the sawtooth is not selected" do
      restart(0x50, frequency: 0x8000, cycles: 256)
      waveform.cycle!
      expect(waveform.accumulator).to eq(0x808000)
    end

    # The 8580 buffers the top bit behind a flip-flop ahead of that switch.
    describe "on the 8580" do
      subject(:waveform) { described_class.new(model: :mos8580) }

      it "leaves the accumulator MSB alone" do
        restart(0x30, frequency: 0x8000, cycles: 256)
        waveform.cycle!
        expect(waveform.accumulator).to eq(0x808000)
      end
    end
  end

  describe "#osc3" do
    it "follows the output on the 6581" do
      restart(0x20, frequency: 0x1000, cycles: 3)
      expect(waveform.osc3).to eq(0x003)
    end

    # Pinned by SID/detect (detect-2-new): the 8580 delays the triangle and
    # sawtooth shapers half a cycle, which OSC3 latches as a whole one.
    describe "on the 8580" do
      subject(:waveform) { described_class.new(model: :mos8580) }

      it "reads the sawtooth a cycle late" do
        restart(0x20, frequency: 0x1000, cycles: 3)
        expect(waveform.osc3).to eq(0x002)
      end

      it "reads the triangle a cycle late" do
        restart(0x10, frequency: 0x1000, cycles: 3)
        expect(waveform.osc3).to eq(0x004)
      end

      it "leaves the audio output on time" do
        restart(0x20, frequency: 0x1000, cycles: 3)
        expect(waveform.output).to eq(0x003)
      end

      it "masks the delayed sawtooth with the pulse on time" do
        waveform.pulse_width_high = 0x0f
        restart(0x60, frequency: 0x1000, cycles: 3)
        expect(waveform.osc3).to eq(0x000)
      end

      it "masks the delayed sawtooth with the noise on time" do
        restart(0xa0, frequency: 0x1000, cycles: 3)
        expect(waveform.osc3).to eq(0x002 & waveform.noise)
      end

      it "follows the output without a triangle or sawtooth" do
        restart(0x40, frequency: 0x1000, cycles: 3)
        expect(waveform.osc3).to eq(0xfff)
      end
    end
  end

  # SID/osc3-wave0: waveform 0 leaves the DAC input floating.
  describe "floating output" do
    # Pulse with the width at zero reads high, so the DAC has a value to hold.
    before do
      start(0x40)
      waveform.cycle!
      waveform.control = 0x00
    end

    it "holds the last value driven onto it" do
      described_class::FLOATING_OUTPUT_TTL.pred.times { waveform.cycle! }
      expect(waveform.output).to eq(0xfff)
    end

    it "drains to zero once the charge is gone" do
      described_class::FLOATING_OUTPUT_TTL.times { waveform.cycle! }
      expect(waveform.output).to eq(0x000)
    end

    it "reads zero before any waveform has driven it" do
      expect(described_class.new.output).to eq(0x000)
    end
  end

  describe "#output" do
    it "is silent with no waveform selected" do
      expect(waveform.output).to eq(0x000)
    end

    it "ANDs the selected waveforms together" do
      restart(0x30, frequency: 0x0000)
      expect(waveform.output).to eq(0x000)
    end

    it "follows the single selected waveform" do
      start(0x20)
      expect(waveform.output).to eq(0x555)
    end
  end

  describe "hard sync" do
    let(:dest) { described_class.new }

    before do
      waveform.sync_dest = dest
      dest.sync_source = waveform
      dest.control = 0x12
    end

    it "resets the destination when the source MSB rises" do
      restart(0x20, frequency: 0x8000, cycles: 256)
      waveform.synchronize!
      expect(dest.accumulator).to eq(0x000000)
    end

    it "leaves the destination alone before the MSB rises" do
      restart(0x20, frequency: 0x8000, cycles: 255)
      waveform.synchronize!
      expect(dest.accumulator).to eq(0x555555)
    end

    it "does not sync a destination with the sync bit clear" do
      dest.control = 0x10
      restart(0x20, frequency: 0x8000, cycles: 256)
      waveform.synchronize!
      expect(dest.accumulator).to eq(0x555555)
    end

    # A source synced on the same cycle its own MSB rises swallows the sync.
    it "does not pass on a sync it receives on the same cycle" do
      waveform.sync_source.control = 0x08
      restart(0x22, frequency: 0x8000, cycles: 256)
      waveform.synchronize!
      expect(dest.accumulator).to eq(0x555555)
    end
  end
end
