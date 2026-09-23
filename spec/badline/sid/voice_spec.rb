# frozen_string_literal: true

require "spec_helper"

describe Badline::SID::Voice do
  subject(:voice) { described_class.new }

  let(:wave_zero) { described_class::WAVE_ZERO[:mos6581] }
  let(:dc_offset) { described_class::DC_OFFSET[:mos6581] }

  # Sawtooth of the power-on accumulator, with the gate open up to the
  # first attack step.
  def gate_sawtooth
    voice.control = 0x21
    12.times { voice.cycle! }
  end

  it "sits on the DC offset while the envelope is closed" do
    voice.control = 0x20
    expect(voice.output).to eq(dc_offset)
  end

  it "swings the waveform around the DAC midpoint" do
    gate_sawtooth
    expect(voice.output).to eq(0x555 - wave_zero + dc_offset)
  end

  it "scales the swing by the envelope" do
    voice.control = 0x21
    ((9 * 4) + 3).times { voice.cycle! }
    expect(voice.output).to eq(((0x555 - wave_zero) * 4) + dc_offset)
  end

  it "swings below the midpoint for a waveform under it" do
    voice.waveform.pulse_width_low = 0xff
    voice.waveform.pulse_width_high = 0x0f
    voice.control = 0x41
    12.times { voice.cycle! }
    expect(voice.output).to eq(dc_offset - wave_zero)
  end

  it "opens the gate on a control write" do
    gate_sawtooth
    expect(voice.envelope.state).to eq(:attack)
  end

  it "advances the oscillator on every cycle" do
    voice.waveform.frequency_low = 0x10
    voice.cycle!
    expect(voice.waveform.accumulator).to eq(0x555565)
  end

  describe "the 8580" do
    subject(:voice) { described_class.new(model: :mos8580) }

    it "centres the waveform DAC and carries no DC offset" do
      voice.control = 0x20
      expect(voice.output).to eq(0)
    end
  end
end
