# frozen_string_literal: true

require "spec_helper"
require "badline/vic20"

describe Badline::Vic20::Sound do
  subject(:sound) { described_class.new(clock, 1_108_405) }

  let(:clock) { Struct.new(:cycles).new(0) }

  # The cycles at which the next `count` shifts of `voice` show.
  def shift_cycles(voice, count)
    previous = sound.shift_register(voice)
    times = []
    while times.size < count
      clock.cycles += 1
      current = sound.shift_register(voice)
      times << clock.cycles if current != previous
      previous = current
    end
    times
  end

  def gaps(times) = times.each_cons(2).map { |earlier, later| later - earlier }

  # The voice's output bit after each of its next `count` shifts.
  def outputs(voice, count)
    Array.new(count) do
      shift_cycles(voice, 1)
      sound.shift_register(voice) & 1
    end
  end

  # Turns `voice` on or off for each of its next shifts, a character of
  # `bits` a shift, then leaves it on.
  def load(voice, bits)
    bits.each_char do |bit|
      sound.write(0x0a + voice, bit == "1" ? 0xff : 0x7f)
      shift_cycles(voice, 1)
    end
    sound.write(0x0a + voice, 0xff)
  end

  def run(cycles)
    clock.cycles += cycles
    sound.drain_samples
  end

  before { sound.record(rate: 44_100) }

  describe "a tone voice's counter" do
    # Pinned by xvic recordings: $900A=$FE, $80 and $FF measure 4329.70,
    # 34.0922 and 33.8256 Hz, $900B=$F0 577.29 Hz, and $900C=$F0 and $A0
    # 1154.59 and 182.30 Hz: the clock over 16 shifts of these periods.
    {
      [0x0a, 0xfe] => 16, [0x0a, 0x80] => 127 * 16, [0x0a, 0xff] => 128 * 16,
      [0x0b, 0xf0] => 15 * 8, [0x0c, 0xf0] => 15 * 4, [0x0c, 0xa0] => 95 * 4
    }.each do |(register, value), cycles|
      it "shifts every #{cycles} cycles with $#{format('%02X', value)} in $#{format('%04X', 0x9000 + register)}" do
        sound.write(register, value)
        shift_cycles(register - 0x0a, 1)
        expect(gaps(shift_cycles(register - 0x0a, 3))).to eq([cycles, cycles])
      end
    end

    it "takes a new value at its next reload" do
      sound.write(0x0a, 0x80)
      first = shift_cycles(0, 1).first
      sound.write(0x0a, 0xfe)
      expect(gaps([first] + shift_cycles(0, 2))).to eq([127 * 16, 16])
    end
  end

  describe "a tone voice" do
    it "plays 8 shifts high and 8 low" do
      sound.write(0x0a, 0xfe)
      expect(outputs(0, 16)).to eq(([1] * 8) + ([0] * 8))
    end

    it "shifts its pattern out to silence once off" do
      sound.write(0x0a, 0xfe)
      shift_cycles(0, 3)
      sound.write(0x0a, 0x7e)
      expect(outputs(0, 8)).to eq([0] * 8)
    end

    # Pinned by xvic: the harmonics of a bass voice loaded with 10101010,
    # 11000000, 10000000 and 11101000 this way, one shift every 2048
    # cycles, match these shift registers' to 0.1 dB in its recordings.
    it "keeps a pattern loaded by turning it on and off, inverted every 8 shifts" do
      sound.write(0x0a, 0x7f)
      load(0, "10101010")
      expect(outputs(0, 16)).to eq([0, 1, 0, 1, 0, 1, 0, 1, 1, 0, 1, 0, 1, 0, 1, 0])
    end
  end

  describe "the noise voice" do
    def step_lfsr
      clock.cycles += 2
      sound.lfsr
    end

    before do
      sound.write(0x0d, 0xfe)
      clock.cycles += 2 * 128
    end

    it "steps its LFSR every 2 cycles with $FE in $900D" do
      sound.lfsr
      expect(Array.new(4) { [sound.lfsr, step_lfsr] }.none? { |before, after| before == after }).to be(true)
    end

    # Pinned by xvic: its noise at $FE and $FD repeats every 0.11825 s and
    # 0.2365 s, 65535 steps of 2 and 4 cycles (autocorrelation 0.98).
    it "steps a 16-bit LFSR through 65535 states" do
      start = sound.lfsr
      expect((1..65_536).find { step_lfsr == start }).to eq(65_535)
    end

    it "fills the LFSR with ones while off" do
      20.times { step_lfsr }
      sound.write(0x0d, 0x7e)
      clock.cycles += 1
      expect(Array.new(16) { step_lfsr }.last).to eq(0xffff)
    end

    it "shifts its shift register each time the LFSR's bit 0 rises" do
      steps = Array.new(200) { [sound.lfsr & 1, sound.shift_register(3), step_lfsr & 1, sound.shift_register(3)] }
      expect(steps.all? { |was, before, now, after| (before != after) == (was.zero? && now == 1) }).to be(true)
    end

    it "is silent while off" do
      sound.write(0x0e, 15)
      sound.write(0x0d, 0x7e)
      run(100_000)
      expect(run(100_000).uniq).to eq([0])
    end
  end

  describe "the volume" do
    def peak(volume)
      sound.write(0x0e, volume)
      run(200_000).last(4_000).max
    end

    it "takes $900E's low 4 bits" do
      sound.write(0x0e, 0xa7)
      expect(sound.volume).to eq(7)
    end

    it "scales the voices" do
      sound.write(0x0a, 0xf0)
      expect(peak(15).fdiv(peak(5))).to be_within(0.01).of(3.0)
    end

    # Pinned by xvic: a step of the volume from 0 to 15 with every voice
    # off peaks at 0.218 of a voice turned on at volume 15.
    it "steps the output with every voice off, by 2/9 of a voice" do
      sound.write(0x0e, 15)
      idle = run(5_000).max
      sound.write(0x0a, 0xff)
      expect(idle.fdiv(run(5_000).max)).to be_within(0.005).of(2.0 / 9)
    end
  end

  describe "#drain_samples" do
    it "takes the samples recorded since the last drain" do
      expect([run(1_108_405).size, run(110_841).size]).to eq([44_100, 4_410])
    end

    it "takes nothing before recording starts" do
      idle = described_class.new(clock, 1_108_405)
      clock.cycles += 10_000
      expect(idle.drain_samples).to eq([])
    end
  end
end
