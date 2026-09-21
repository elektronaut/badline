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

    it "holds the seed until accumulator bit 19 rises" do
      restart(0x80, frequency: 0x8000, cycles: 15)
      expect(waveform.shift_register).to eq(0x7ffff8)
    end

    it "shifts left when accumulator bit 19 rises, feeding back bits 22 and 17" do
      restart(0x80, frequency: 0x8000, cycles: 16)
      expect(waveform.shift_register).to eq(0x7ffff0)
    end

    it "shifts once for each rise of accumulator bit 19" do
      restart(0x80, frequency: 0x8000, cycles: 48)
      expect(waveform.noise).to eq(0xfc0)
    end

    it "clears the LFSR while the test bit is held" do
      waveform.control = 0x88
      expect(waveform.noise).to eq(0x000)
    end

    it "refills the LFSR when the test bit is released" do
      waveform.control = 0x88
      waveform.control = 0x80
      expect(waveform.noise).to eq(0xfe0)
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
