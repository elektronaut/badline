# frozen_string_literal: true

require "spec_helper"
require "badline/chips/riot"

# Timings count φ2 cycles from the one the CPU writes the timer on, as the
# MOS 6532 datasheet's figure 3 (Timer Interrupt Timing, Commodore
# Semiconductor Group, 2/81) numbers its φ2 pulses: 52 written at ÷8 reads
# 25 on pulse 213 and 0 on pulse 415, and the interrupt comes on pulse 416
# with the timer reading $FF. Its fifth point reads $AC on pulse 500, a
# cycle out from its own worked example, where $E4 is 27 cycles after the
# interrupt; the counter here follows the worked example and reads $AB.
describe Badline::Chips::RIOT::Timer do
  subject(:riot) { Badline::Chips::RIOT.new }

  def run(cycles) = cycles.times { riot.cycle! }

  # What the timer reads after each of the given number of cycles.
  def trace(cycles)
    Array.new(cycles) do
      riot.cycle!
      yield
    end
  end

  def counter = riot.timer.counter

  def flag? = riot.timer.flag

  # A timer write with A4 set; A1-A0 pick ÷1, ÷8, ÷64 or ÷1024 and A3
  # enables the interrupt.
  def start_timer(value, interval: 0, irq: false)
    riot.poke(0x14 | interval | (irq ? 0x08 : 0x00), value)
  end

  describe "the datasheet's example, 52 at ÷8" do
    before { start_timer(52, interval: 1) }

    it "reads 51 from the cycle after the write and 50 from cycle 8" do
      expect(trace(9) { counter }).to eq(Array.new(7, 51) + [50, 50])
    end

    it "reads 25 on cycle 213" do
      run(213)
      expect(counter).to eq(25)
    end

    it "reads 0 through cycle 415, the flag still clear" do
      run(407)
      expect(trace(8) { [counter, flag?] }).to all(eq([0, false]))
    end

    it "sets the flag on cycle 416, reading $FF" do
      run(414)
      expect(trace(2) { [counter, flag?] }).to eq([[0, false], [0xff, true]])
    end

    it "counts every cycle once the flag is up, $E4 27 cycles after" do
      run(416 + 27)
      expect(counter).to eq(0xe4)
    end
  end

  describe "the dividers" do
    { 0 => 1, 1 => 8, 2 => 64, 3 => 1024 }.each do |interval, divider|
      it "sets the flag after 3 x #{divider} cycles at ÷#{divider}" do
        start_timer(3, interval:)
        run((3 * divider) - 2)
        expect(trace(2) { flag? }).to eq([false, true])
      end
    end
  end

  it "times out on the write itself when written 0" do
    start_timer(0, interval: 3)
    expect([counter, flag?]).to eq([0xff, true])
  end

  it "sets the flag again on each count through 0 after the timeout" do
    start_timer(1)
    run(2)
    riot.peek(0x04)
    expect(trace(255) { flag? }).to eq(Array.new(254, false) + [true])
  end

  it "keeps counting every cycle after a read, until the next write" do
    start_timer(1, interval: 3)
    run(1024)
    riot.peek(0x04)
    expect(trace(2) { counter }).to eq([0xfe, 0xfd])
  end

  it "puts the prescaler back on a write" do
    start_timer(2, interval: 1)
    run(5)
    start_timer(2, interval: 1)
    expect(trace(9) { counter }).to eq(Array.new(7, 1) + [0, 0])
  end

  describe "the flag" do
    before do
      start_timer(2)
      run(1)
    end

    it "stays up on a read on the cycle that sets it" do
      run(1)
      riot.peek(0x04)
      expect(flag?).to be(true)
    end

    it "clears on a read after that cycle" do
      run(2)
      riot.peek(0x04)
      expect(flag?).to be(false)
    end

    it "clears on a write" do
      run(2)
      start_timer(9)
      expect(flag?).to be(false)
    end

    it "stays up across a read of the interrupt flags" do
      run(2)
      riot.peek(0x05)
      expect(flag?).to be(true)
    end
  end

  describe "the interrupt" do
    it "pulls IRQ once the flag is up while A3 enabled it on the write" do
      start_timer(2, irq: true)
      expect(trace(2) { riot.irq? }).to eq([false, true])
    end

    it "leaves IRQ alone while A3 was clear on the write" do
      start_timer(2)
      run(2)
      expect([flag?, riot.irq?]).to eq([true, false])
    end

    it "takes the enable from A3 on a read of the timer too" do
      start_timer(5)
      riot.peek(0x0c)
      run(5)
      expect(riot.irq?).to be(true)
    end

    it "releases IRQ on a read with A3 clear on the cycle that sets the flag" do
      start_timer(1, irq: true)
      run(1)
      riot.peek(0x04)
      expect([flag?, riot.irq?]).to eq([true, false])
    end

    it "is disabled by reset, the timer counting on" do
      start_timer(9, irq: true)
      riot.reset!
      run(9)
      expect([counter, riot.irq?]).to eq([0xff, false])
    end
  end
end
