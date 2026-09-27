# frozen_string_literal: true

require "spec_helper"

# Timings count φ2 cycles from the one the CPU writes the register on, as
# for timer 1: loaded with N, the counter reads N on the cycle after and
# the flag is up on cycle N + 2.
describe Badline::VIA::Timer2 do
  subject(:via) { Badline::VIA.new(start: 0x1800) }

  def run(cycles) = cycles.times { via.cycle! }

  # What the block reads after each of the given number of cycles.
  def trace(cycles)
    Array.new(cycles) do
      via.cycle!
      yield
    end
  end

  # What the block reads after each of the given number of PB6 pulses.
  def pulses(count)
    Array.new(count) do
      via.pb6 = false
      via.pb6 = true
      yield
    end
  end

  def flag? = via.interrupt_flags.anybits?(0x20)

  def start_timer(value)
    via.poke(0x1808, value & 0xff)
    via.poke(0x1809, value >> 8)
  end

  describe "in one-shot mode" do
    it "loads the low byte from its latch and the high byte from the write" do
      start_timer(0x0203)
      expect(trace(2) { via.timer2 }).to eq([0x0203, 0x0202])
    end

    it "counts N down to 0, $FFFF, and rolls on without reloading" do
      start_timer(2)
      expect(trace(6) { via.timer2 }).to eq([2, 1, 0, 0xffff, 0xfffe, 0xfffd])
    end

    it "sets the flag on cycle N + 2" do
      start_timer(4)
      expect(trace(6) { flag? }).to eq(Array.new(5, false) + [true])
    end

    it "sets the flag only once per load" do
      start_timer(1)
      run(3)
      via.peek(0x1808)
      run(0x10001)
      expect(flag?).to be(false)
    end

    it "clears the flag on a read of the low counter byte" do
      start_timer(1)
      run(3)
      via.peek(0x1808)
      expect(flag?).to be(false)
    end

    it "clears the flag on a write of the high counter byte" do
      start_timer(1)
      run(3)
      via.poke(0x1809, 0x10)
      expect(flag?).to be(false)
    end

    it "reads the counter at $8 and $9" do
      start_timer(0xabcd)
      via.cycle!
      expect([via.peek(0x1808), via.peek(0x1809)]).to eq([0xcd, 0xab])
    end

    it "ignores PB6" do
      start_timer(3)
      via.pb6 = false
      expect(via.timer2).to eq(3)
    end
  end

  describe "counting PB6 pulses" do
    before { via.poke(0x180b, 0x20) }

    it "stands still on φ2" do
      start_timer(3)
      run(10)
      expect(via.timer2).to eq(3)
    end

    it "counts falling edges only" do
      start_timer(3)
      via.pb6 = false
      via.pb6 = true
      expect(via.timer2).to eq(2)
    end

    it "sets the flag on the pulse that takes it past zero, the N + 1st" do
      start_timer(2)
      expect(pulses(4) { flag? }).to eq([false, false, true, true])
    end

    it "counts down on the first cycle after switching back to φ2" do
      start_timer(5)
      run(3)
      via.poke(0x180b, 0x00)
      expect(trace(2) { via.timer2 }).to eq([4, 3])
    end

    it "sets the flag only once per load" do
      start_timer(0)
      pulses(1) { via.peek(0x1808) }
      expect(pulses(0x10000) { flag? }).to all(be(false))
    end
  end

  describe "serving the shift register" do
    before { via.poke(0x180b, 0x14) } # mode 5, shift out under timer 2

    it "reloads its low byte from the latch after each low underflow" do
      start_timer(0x0302)
      expect(trace(8) { via.timer2 })
        .to eq([0x0302, 0x0301, 0x0300, 0x02ff, 0x0202, 0x0201, 0x0200, 0x01ff])
    end

    it "still sets its flag when the high byte borrows past zero" do
      start_timer(0x0001)
      run(3)
      expect(flag?).to be(true)
    end
  end

  describe "#low_underflowed" do
    subject(:timer) { described_class.new }

    def underflows(cycles)
      Array.new(cycles) do
        timer.cycle!(true)
        timer.low_underflowed
      end
    end

    it "says when the low byte underflowed, every N + 2 cycles in the shift register's service" do
      timer.latch_low = 0x01
      timer.load(0x00)
      expect(underflows(7)).to eq([false, false, true, false, false, true, false])
    end
  end
end
