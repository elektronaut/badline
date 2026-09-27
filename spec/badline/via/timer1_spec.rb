# frozen_string_literal: true

require "spec_helper"

# Timings count φ2 cycles from the one the CPU writes the register on. The
# datasheet puts the interrupt N + 1.5 cycles after the write of N: the
# counter reads N on the cycle after, reaches 0 on cycle N + 1, and the
# flag is up when it reads $FFFF on cycle N + 2.
describe Badline::VIA::Timer1 do
  subject(:via) { Badline::VIA.new(start: 0x1800) }

  def run(cycles) = cycles.times { via.cycle! }

  # What the block reads after each of the given number of cycles.
  def trace(cycles)
    Array.new(cycles) do
      via.cycle!
      yield
    end
  end

  def flag? = via.interrupt_flags.anybits?(0x40)

  def start_timer(value)
    via.poke(0x1804, value & 0xff)
    via.poke(0x1805, value >> 8)
  end

  # A one-shot load that has timed out, which leaves the timer unarmed.
  def spend_one_shot
    via.poke(0x180b, 0x00)
    start_timer(1)
    run(4)
  end

  describe "in one-shot mode" do
    it "counts N down to 0 and on to $FFFF, then reloads from the latch" do
      start_timer(3)
      expect(trace(7) { via.timer1 }).to eq([3, 2, 1, 0, 0xffff, 3, 2])
    end

    it "picks up a new latch on the reload after the timeout" do
      start_timer(1)
      via.poke(0x1806, 4)
      expect(trace(5) { via.timer1 }).to eq([1, 0, 0xffff, 4, 3])
    end

    it "sets the flag only on the first timeout, however often it reloads" do
      start_timer(1)
      run(3)
      via.peek(0x1804)
      expect(trace(9) { flag? }).to all(be(false))
    end

    it "loads the counter at the write, whatever the latch gets after" do
      start_timer(0x0105)
      via.poke(0x1806, 0x20)
      via.poke(0x1807, 0x00)
      expect(trace(3) { via.timer1 }).to eq([0x0105, 0x0104, 0x0103])
    end

    it "sets the flag on cycle N + 2, as the counter reads $FFFF" do
      start_timer(5)
      expect(trace(7) { flag? }).to eq(Array.new(6, false) + [true])
    end

    it "sets the flag only once per load" do
      start_timer(2)
      run(4)
      via.peek(0x1804)
      run(0x10002)
      expect(flag?).to be(false)
    end

    it "clears the flag and rearms on the next $5 write" do
      start_timer(2)
      run(4)
      via.poke(0x1805, 0)
      expect(trace(4) { flag? }).to eq([false, false, false, true])
    end

    it "clears the flag on a read of the low counter byte" do
      start_timer(1)
      run(3)
      via.peek(0x1804)
      expect(flag?).to be(false)
    end

    it "leaves the flag alone on a read of the high counter byte" do
      start_timer(1)
      run(3)
      via.peek(0x1805)
      expect(flag?).to be(true)
    end

    it "clears the flag on a write of the high latch byte" do
      start_timer(1)
      run(3)
      via.poke(0x1807, 0)
      expect(flag?).to be(false)
    end

    it "reads the counter at $4 and $5 and the latch at $6 and $7" do
      start_timer(0x1234)
      via.poke(0x1806, 0x78)
      via.poke(0x1807, 0x56)
      via.cycle!
      expect([0x1804, 0x1805, 0x1806, 0x1807].map { |a| via.peek(a) }).to eq([0x34, 0x12, 0x78, 0x56])
    end

    it "leaves the counter alone on latch writes at $6 and $7" do
      via.poke(0x1806, 0x10)
      via.poke(0x1807, 0x00)
      via.cycle!
      expect(via.timer1).not_to eq(0x0010)
    end

    it "drives PB7 low on load and high on timeout when ACR bit 7 is set" do
      via.poke(0x180b, 0x80)
      start_timer(2)
      expect(trace(5) { via.port_b_output[7] }).to eq([0, 0, 0, 1, 1])
    end

    it "holds PB7 high through later timeouts" do
      via.poke(0x180b, 0x80)
      start_timer(1)
      expect(trace(9) { via.port_b_output[7] }).to eq([0, 0, 1, 1, 1, 1, 1, 1, 1])
    end

    it "leaves PB7 to ORB when ACR bit 7 is clear" do
      via.poke(0x1802, 0x80)
      via.poke(0x1800, 0x80)
      start_timer(2)
      via.cycle!
      expect(via.port_b_output[7]).to eq(1)
    end

    # Pinned by viavarious via10 to via13 (test D): PB7 reads high from
    # the ACR write on, then low for good after the timeout.
    it "drives PB7 high when ACR bit 7 turns on after the load, and inverts it on the timeout" do
      start_timer(2)
      via.poke(0x180b, 0x80)
      expect(trace(6) { via.port_b_output[7] }).to eq([1, 1, 1, 0, 0, 0])
    end

    it "leaves PB7 alone when ACR is rewritten with bit 7 still set" do
      via.poke(0x180b, 0x80)
      start_timer(2)
      via.poke(0x180b, 0x80)
      expect(via.port_b_output[7]).to eq(0)
    end

    it "reads PB7 as the timer output, whatever DDRB says" do
      via.poke(0x180b, 0x80)
      start_timer(2)
      via.cycle!
      expect(via.peek(0x1800)[7]).to eq(0)
    end
  end

  describe "in free-running mode" do
    before { via.poke(0x180b, 0x40) }

    it "reloads from the latch on the cycle after $FFFF, a period of N + 2" do
      start_timer(2)
      expect(trace(9) { via.timer1 }).to eq([2, 1, 0, 0xffff, 2, 1, 0, 0xffff, 2])
    end

    it "sets the flag on every timeout" do
      start_timer(2)
      run(4)
      via.peek(0x1804)
      expect(trace(4) { flag? }).to eq([false, false, false, true])
    end

    it "picks up a new latch on the next reload" do
      start_timer(1)
      via.poke(0x1806, 5)
      expect(trace(4) { via.timer1 }).to eq([1, 0, 0xffff, 5])
    end

    # Pinned by viavarious via3 (tests B and D) and via3a (tests B, D, F
    # and H): a timer only ever armed by the one-shot load before it never
    # sets its flag after switching to free-running, whatever the latch.
    it "sets no flag until a $5 write arms it, however often it reloads" do
      spend_one_shot
      via.poke(0x180b, 0x40)
      via.poke(0x1806, 2)
      via.poke(0x1807, 0)
      expect(trace(12) { flag? }).to all(be(false))
    end

    # Pinned by viavarious via10 to via13 (test G): PB7 holds high while
    # the timer runs through its timeouts unarmed.
    it "leaves PB7 alone on timeouts until a $5 write arms it" do
      spend_one_shot
      via.poke(0x180b, 0xc0)
      expect(trace(9) { via.port_b_output[7] }).to all(eq(1))
    end

    it "inverts PB7 on every timeout" do
      via.poke(0x180b, 0xc0)
      start_timer(1)
      expect(trace(9) { via.port_b_output[7] }).to eq([0, 0, 1, 1, 1, 0, 0, 0, 1])
    end
  end
end
