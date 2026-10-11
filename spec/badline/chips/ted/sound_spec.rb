# frozen_string_literal: true

require "spec_helper"
require "badline/plus4"

describe Badline::Chips::TED::Sound do
  subject(:sound) { described_class.new(clock, 886_724) }

  let(:clock) { Struct.new(:cycles).new(0) }

  # The cycles at which `voice` next toggles, `count` times.
  def toggle_cycles(voice, count)
    previous = sound.phase(voice)
    times = []
    while times.size < count
      clock.cycles += 1
      current = sound.phase(voice)
      times << clock.cycles if current != previous
      previous = current
    end
    times
  end

  def gaps(times) = times.each_cons(2).map { |earlier, later| later - earlier }

  def tune(voice, value)
    sound.write(voice.zero? ? 0x0e : 0x0f, value & 0xff)
    sound.write(voice.zero? ? 0x12 : 0x10, value >> 8)
  end

  # What the block gives after each of voice 2's next `count` toggles.
  def at_toggles(count)
    Array.new(count) do
      toggle_cycles(1, 1)
      yield
    end
  end

  def noise_bit = (sound.noise >> 1) & 1

  def level_with(control)
    sound.write(0x11, control)
    sound.level
  end

  def run(cycles)
    clock.cycles += cycles
    sound.drain_samples
  end

  describe "a voice's counter" do
    # Pinned by xplus4 recordings of voice 1: $000, $200, $300, $3F0 and
    # $3FF measure 108.344, 216.900, 434.653, 7389.08 and 108.239 Hz, the
    # clock over 8 * 1023, 8 * 511, 8 * 255, 8 * 15 and 8 * 1024 cycles.
    intervals = { 0x000 => 4 * 1023, 0x200 => 4 * 511, 0x300 => 4 * 255, 0x3f0 => 4 * 15, 0x3ff => 4 * 1024 }
    intervals.each do |value, cycles|
      it "toggles every #{cycles} cycles at $#{format('%03X', value)}" do
        tune(0, value)
        toggle_cycles(0, 1)
        expect(gaps(toggle_cycles(0, 3))).to eq([cycles, cycles])
      end
    end

    it "takes a new frequency at its next toggle" do
      tune(1, 0x200)
      first = toggle_cycles(1, 1).first
      tune(1, 0x3f0)
      expect(gaps([first] + toggle_cycles(1, 2))).to eq([4 * 511, 4 * 15])
    end

    it "counts while its voice is off" do
      tune(0, 0x3f0)
      expect(gaps(toggle_cycles(0, 3))).to eq([60, 60])
    end
  end

  describe "the levels" do
    before { sound.write(0x11, 0x98) }

    # Pinned by xplus4 recordings: one voice held high at volumes 1-8
    # measures 586 to 7754 in steps of 1024, and both 1172, 3284, 5526,
    # 7984, 10658, 13548, 16654 and 19976.
    it "gives one voice high its level for the volume" do
      expect([1, 4, 8].map { |volume| level_with(0x90 | volume) }).to eq([586, 3658, 7754])
    end

    it "gives both voices high more than twice one" do
      expect(level_with(0xb8)).to eq(19_976)
    end

    it "takes volumes 9-15 as 8" do
      expect([level_with(0x9f), sound.volume]).to eq([7754, 8])
    end

    it "is silent at volume 0 and with every voice off" do
      expect([0x90, 0x88].map { |control| level_with(control) }).to eq([0, 0])
    end
  end

  describe "$3FE" do
    it "holds a voice high" do
      sound.write(0x11, 0x18)
      tune(0, 0x3fe)
      clock.cycles += 10_000
      expect(sound.level).to eq(7754)
    end

    # Pinned by xplus4: noise held at $3FE for 20, 21 or 23 frames plays
    # on with the same bits once it leaves.
    it "stops the noise after voice 2's next toggle" do
      tune(1, 0x3fe)
      toggle_cycles(1, 1)
      noise = sound.noise
      clock.cycles += 100_000
      expect(sound.noise).to eq(noise)
    end

    it "starts the voice a whole interval after it leaves" do
      tune(0, 0x3fe)
      clock.cycles += 10_000
      sound.write(0x0e, 0xf0)
      expect(toggle_cycles(0, 1)).to eq([10_002 + (4 * 15)])
    end
  end

  describe "the noise" do
    before { tune(1, 0x3d7) }

    # Pinned by xplus4 recordings at $3D7 after a reload: 21,306 bits
    # follow this recurrence over GF(2) with period 255, and start
    # 1100110111101110.
    it "plays bits 1, 4, 5 and 7 fed back from all ones after a reload" do
      sound.write(0x11, 0xc8)
      sound.write(0x11, 0x48)
      expect([noise_bit] + at_toggles(15) { noise_bit }).to eq([1, 1, 0, 0, 1, 1, 0, 1, 1, 1, 1, 0, 1, 1, 1, 0])
    end

    it "runs through 255 states" do
      start = sound.noise
      expect(at_toggles(255) { sound.noise }.index(start)).to eq(254)
    end

    it "is the voice's output with only bit 6 set" do
      sound.write(0x11, 0x48)
      expect(at_toggles(8) { sound.level == noise_bit * 7754 }.uniq).to eq([true])
    end

    it "gives way to the square wave with bits 5 and 6 set" do
      sound.write(0x11, 0x68)
      expect(at_toggles(8) { sound.level == sound.phase(1) * 7754 }.uniq).to eq([true])
    end
  end

  describe "the reload bit" do
    before do
      tune(0, 0x200)
      tune(1, 0x3d7)
      sound.write(0x11, 0xd8)
    end

    it "holds the voices high and the noise silent" do
      clock.cycles += 10_000
      expect([sound.reloading?, sound.phase(0), sound.level]).to eq([true, 1, 7754])
    end

    it "fills the noise with ones" do
      expect(sound.noise).to eq(0xff)
    end

    it "starts each voice on a whole high half-wave once written clear" do
      clock.cycles += 10_000
      sound.write(0x11, 0x18)
      expect(toggle_cycles(0, 1)).to eq([10_002 + (4 * 511)])
    end
  end

  describe "running the voices" do
    let(:host) { described_class.new(clock, 886_724) }

    def state(chip) = [chip.noise, chip.phase(0), chip.phase(1), chip.level]

    def play(chip)
      chip.write(0x0f, 0xd7)
      chip.write(0x10, 0x03)
      chip.write(0x11, 0x58)
    end

    it "leaves them in the same state whether or not they are recorded" do
      host.record(rate: 44_100)
      [sound, host].each { |chip| play(chip) }
      clock.cycles += 123_457
      expect(state(sound)).to eq(state(host))
    end
  end

  describe "#drain_samples" do
    before { sound.record(rate: 44_100) }

    it "takes the samples recorded since the last drain" do
      expect([run(886_724).size, run(88_672).size]).to eq([44_100, 4_410])
    end

    it "takes nothing before recording starts" do
      idle = described_class.new(clock, 886_724)
      clock.cycles += 10_000
      expect(idle.drain_samples).to eq([])
    end

    it "lets a level held high fall away through the coupling capacitor" do
      sound.write(0x11, 0x98)
      first = run(4_000).first
      expect(run(886_724).last).to be < first / 10
    end
  end
end
