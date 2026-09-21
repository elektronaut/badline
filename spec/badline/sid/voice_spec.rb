# frozen_string_literal: true

require "spec_helper"

describe Badline::SID::Voice do
  subject(:voice) { described_class.new }

  # Sawtooth of the power-on accumulator, with the gate open.
  def gate_sawtooth
    voice.control = 0x21
    9.times { voice.cycle! }
  end

  it "sits on the DC offset while the envelope is closed" do
    voice.control = 0x20
    expect(voice.output).to eq(described_class::DC_OFFSET)
  end

  it "swings the waveform around the DAC midpoint" do
    gate_sawtooth
    expect(voice.output).to eq(0x555 - described_class::WAVE_ZERO + described_class::DC_OFFSET)
  end

  it "scales the swing by the envelope" do
    voice.control = 0x21
    (9 * 4).times { voice.cycle! }
    expect(voice.output).to eq(((0x555 - described_class::WAVE_ZERO) * 4) + described_class::DC_OFFSET)
  end

  it "swings below the midpoint for a waveform under it" do
    voice.waveform.pulse_width_low = 0xff
    voice.waveform.pulse_width_high = 0x0f
    voice.control = 0x41
    9.times { voice.cycle! }
    expect(voice.output).to eq(described_class::DC_OFFSET - described_class::WAVE_ZERO)
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
end
