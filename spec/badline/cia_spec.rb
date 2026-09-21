# frozen_string_literal: true

require "spec_helper"

describe Badline::CIA do
  subject(:cia) { described_class.new(start: 0xdc00) }

  it "has a default value for data dir A" do
    expect(cia[0xdc02]).to eq(0xff)
  end

  it "has a default value for data dir B" do
    expect(cia[0xdc03]).to eq(0x00)
  end

  it "repeats every 16 bytes" do
    expect(cia[0xdc12]).to eq(0xff)
  end

  describe "PB4 level-change handler (light pen line)" do
    let(:edges) { [] }

    before do
      cia.on_port_b4_change { |high| edges << high }
      cia.poke(0xdc03, 0xff) # DDR B: all output
      cia.poke(0xdc01, 0xff) # PB high
    end

    it "reports the new level when PB4 is driven low" do
      cia.poke(0xdc01, 0x00)
      expect(edges).to eq([false])
    end

    it "reports a full pulse as both edges" do
      cia.poke(0xdc01, 0x00)
      cia.poke(0xdc01, 0xff)
      expect(edges).to eq([false, true])
    end

    it "does not fire while PB4 stays high" do
      cia.poke(0xdc01, 0x10) # other lines fall, bit 4 stays set
      expect(edges).to be_empty
    end

    it "does not fire when the line is an input" do
      cia.poke(0xdc03, 0x00) # all input: the line floats high
      cia.poke(0xdc01, 0x00)
      expect(edges).to be_empty
    end

    it "fires when a DDR change starts driving a low PB4" do
      cia.poke(0xdc03, 0x00)
      cia.poke(0xdc01, 0x00) # latched low, but the line is an input
      cia.poke(0xdc03, 0x10) # output now drives it low
      expect(edges).to eq([false])
    end
  end

  describe "time of day clock" do
    def advance_one_tenth
      98_525.times { cia.cycle! }
    end

    context "when first powered on" do
      specify { expect(cia[0xdc0b]).to eq(0x12) }
      specify { expect(cia[0xdc0a]).to eq(0x00) }
      specify { expect(cia[0xdc09]).to eq(0x00) }
      specify { expect(cia[0xdc08]).to eq(0x00) }
    end

    it "routes register writes to the clock" do
      cia.poke(0xdc09, 0x31)
      expect(cia[0xdc09]).to eq(0x31)
    end

    it "advances a tenth after clock_hz/10 cycles" do
      advance_one_tenth
      expect(cia[0xdc08]).to eq(0x01)
    end

    context "with the alarm armed" do
      before do
        cia.interrupt_control.alarm = true
        cia.control_b.alarm = true
        cia.poke(0xdc0b, 0x12)
        cia.poke(0xdc0a, 0x00)
        cia.poke(0xdc09, 0x00)
        cia.poke(0xdc08, 0x01)
        cia.control_b.alarm = false
      end

      it "does not fire before the clock matches" do
        expect(cia.interrupt_status.alarm?).to be(false)
      end

      it "writes the alarm without changing the clock" do
        expect(cia[0xdc08]).to eq(0x00)
      end

      it "raises the alarm flag when the clock matches" do
        advance_one_tenth
        expect(cia.interrupt_status.alarm?).to be(true)
      end

      it "interrupts the cycle after the clock matches" do
        advance_one_tenth
        cia.cycle!
        expect(cia.interrupted?).to be(true)
      end
    end
  end

  describe "interrupt control register" do
    before { cia.interrupt_status.timer_a = true }

    specify { expect(cia[0xdc0d]).to eq(0x01) }

    it "is cleared after reading" do
      cia.peek(0xdc0d)
      expect(cia[0xdc0d]).to eq(0x00)
    end
  end

  describe "the interrupt line" do
    before do
      cia.control_a.start = true
      cia.timer_a = 0x01
      cia.timer_a_latch = 0xff # reloads high so it won't underflow again soon
    end

    context "when the source is enabled" do
      before do
        cia.interrupt_control.timer_a = true
        3.times { cia.cycle! } # underflow; the line asserts on the next cycle
      end

      it "stays asserted across cycles until acknowledged" do
        5.times { cia.cycle! }
        expect(cia.interrupted?).to be(true)
      end

      it "is released after reading the interrupt control register" do
        cia.peek(0xdc0d)
        expect(cia.interrupted?).to be(false)
      end
    end

    context "when the source is masked" do
      before do
        cia.interrupt_control.timer_a = false
        3.times { cia.cycle! } # underflow with the source disabled
      end

      it "still records the event in the status register" do
        expect(cia.interrupt_status.timer_a?).to be(true)
      end

      it "does not assert the interrupt line" do
        expect(cia.interrupted?).to be(false)
      end
    end
  end

  describe "timer A" do
    before do
      cia.interrupt_control.timer_a = true
      cia.control_a.start = true
      cia.timer_a = 0xff
      cia.timer_a_latch = 0x43
      3.times { cia.cycle! } # counting starts once the pipeline fills
    end

    specify { expect(cia.timer_a).to eq(0xfe) }
    specify { expect(cia.interrupt_status.timer_a?).to be(false) }
    specify { expect(cia.interrupted?).to be(false) }

    context "when reaching zero" do
      before { 254.times { cia.cycle! } }

      specify { expect(cia.timer_a).to eq(0x00) }
      specify { expect(cia.interrupt_status.timer_a?).to be(true) }
      specify { expect(cia.interrupted?).to be(false) }
      specify { expect(cia.control_a.start?).to be(true) }
    end

    context "when a cycle has passed after reaching zero" do
      before { 255.times { cia.cycle! } }

      specify { expect(cia.timer_a).to eq(0x43) }
      specify { expect(cia.interrupted?).to be(true) }
    end

    describe "setting the latch" do
      before do
        cia.poke(0xdc04, 0xcd)
        cia.poke(0xdc05, 0xab)
      end

      specify { expect(cia.timer_a_latch).to eq(0xabcd) }

      it "loads the counter when the timer is stopped" do
        cia.control_a.start = false
        cia.poke(0xdc05, 0xab)
        expect(cia.timer_a).to eq(0xabcd)
      end

      it "does not load the counter while the timer is running" do
        cia.control_a.start = true
        cia.timer_a = 0x1000
        cia.poke(0xdc05, 0xab)
        expect(cia.timer_a).to eq(0x1000)
      end
    end

    describe "starting through the control register" do
      before do
        cia.control_a.start = false
        2.times { cia.cycle! } # drain the pipeline
        cia.timer_a = 0x10
        cia.poke(0xdc0e, 0x01)
      end

      it "delays the first count by the pipeline latency" do
        2.times { cia.cycle! }
        expect(cia.timer_a).to eq(0x10)
      end

      it "counts once the pipeline is filled" do
        3.times { cia.cycle! }
        expect(cia.timer_a).to eq(0x0f)
      end

      it "does not delay an already running timer" do
        3.times { cia.cycle! }
        cia.poke(0xdc0e, 0x01)
        cia.cycle!
        expect(cia.timer_a).to eq(0x0e)
      end
    end

    describe "force load" do
      before do
        cia.timer_a = 0x1000
        cia.timer_a_latch = 0x43
        cia.poke(0xdc0e, 0x10)
      end

      it "copies the latch into the counter one tick after the write" do
        2.times { cia.cycle! }
        expect(cia.timer_a).to eq(0x43)
      end

      it "does not retain the load bit in the control register" do
        expect(cia.control_a.load?).to be(false)
      end
    end

    context "when in one-shot mode" do
      before do
        cia.control_a.run_mode = true
        254.times { cia.cycle! }
      end

      specify { expect(cia.control_a.start?).to be(false) }
    end

    context "when disabled" do
      before do
        cia.control_a.start = false
        2.times { cia.cycle! } # counting drains out of the pipeline
      end

      it "is not decremented" do
        cia.timer_a = 0xffff
        cia.cycle!
        expect(cia.timer_a).to eq(0xffff)
      end
    end

    context "when counting the CNT pin" do
      before do
        cia.control_a.in_mode = true
        2.times { cia.cycle! } # φ2 pulses drain out of the pipeline
      end

      it "is not decremented" do
        cia.timer_a = 0xffff
        cia.cycle!
        expect(cia.timer_a).to eq(0xffff)
      end
    end
  end

  describe "timer B" do
    before do
      cia.interrupt_control.timer_b = true
      cia.control_b.start = true
      cia.timer_b = 0xff
      cia.timer_b_latch = 0x43
      3.times { cia.cycle! } # counting starts once the pipeline fills
    end

    specify { expect(cia.timer_b).to eq(0xfe) }
    specify { expect(cia.interrupt_status.timer_b?).to be(false) }
    specify { expect(cia.interrupted?).to be(false) }

    context "when reaching zero" do
      before { 254.times { cia.cycle! } }

      specify { expect(cia.timer_b).to eq(0x00) }
      specify { expect(cia.interrupt_status.timer_b?).to be(true) }
      specify { expect(cia.interrupted?).to be(false) }
      specify { expect(cia.control_b.start?).to be(true) }
    end

    context "when a cycle has passed after reaching zero" do
      before { 255.times { cia.cycle! } }

      specify { expect(cia.timer_b).to eq(0x43) }
      specify { expect(cia.interrupted?).to be(true) }
    end

    describe "setting the latch" do
      before do
        cia.poke(0xdc06, 0x78)
        cia.poke(0xdc07, 0x56)
      end

      specify { expect(cia.timer_b_latch).to eq(0x5678) }
    end

    context "when in one-shot mode" do
      before do
        cia.control_b.run_mode = true
        254.times { cia.cycle! }
      end

      specify { expect(cia.control_b.start?).to be(false) }
    end

    context "when disabled" do
      before do
        cia.control_b.start = false
        2.times { cia.cycle! } # counting drains out of the pipeline
      end

      it "is not decremented" do
        cia.timer_b = 0xffff
        cia.cycle!
        expect(cia.timer_b).to eq(0xffff)
      end
    end

    context "when counting the CNT pin" do
      before do
        cia.control_b.start = true
        cia.control_b.in_cnt = true
        2.times { cia.cycle! } # φ2 pulses drain out of the pipeline
      end

      it "never decrements" do
        cia.timer_b = 0xffff
        4.times { cia.cycle! }
        expect(cia.timer_b).to eq(0xffff)
      end
    end

    context "when counting timer A underflows" do
      before do
        cia.control_b.start = true
        cia.control_b.in_timer_a = true
        cia.timer_b = 0x05
        cia.control_a.start = true
        cia.timer_a = 0x02
        cia.timer_a_latch = 0x02
      end

      it "decrements only when timer A reaches zero" do
        4.times { cia.cycle! } # pipeline, timer A 2 -> 1 -> 0, underflow
        expect(cia.timer_b).to eq(0x04)
      end

      it "does not decrement while timer A is still counting" do
        3.times { cia.cycle! } # pipeline, timer A 2 -> 1
        expect(cia.timer_b).to eq(0x05)
      end
    end
  end

  describe "timer output on port B" do
    context "with timer A in pulse mode" do
      before do
        cia.control_a.output = true
        cia.control_a.start = true
        cia.timer_a = 0x01
        cia.timer_a_latch = 0x10
      end

      it "drives PB6 high on the underflow cycle" do
        3.times { cia.cycle! }
        expect(cia[0xdc01][6]).to eq(1)
      end

      it "drives PB6 low on non-underflow cycles" do
        3.times { cia.cycle! } # underflow
        cia.cycle! # reload to 0x10, no underflow
        expect(cia[0xdc01][6]).to eq(0)
      end
    end

    context "with timer A in toggle mode" do
      before do
        cia.control_a.output = true
        cia.control_a.out_mode = true
        cia.control_a.start = true
        cia.timer_a = 0x01
        cia.timer_a_latch = 0x01
      end

      it "drives PB6 low after the first underflow" do
        3.times { cia.cycle! }
        expect(cia[0xdc01][6]).to eq(0)
      end

      it "drives PB6 high after the second underflow" do
        5.times { cia.cycle! } # reload after the first, count back to zero
        expect(cia[0xdc01][6]).to eq(1)
      end
    end

    context "with timer B in pulse mode" do
      before do
        cia.control_b.output = true
        cia.control_b.start = true
        cia.timer_b = 0x01
        cia.timer_b_latch = 0x10
      end

      it "drives PB7 high on the underflow cycle" do
        3.times { cia.cycle! }
        expect(cia[0xdc01][7]).to eq(1)
      end
    end

    context "when restarting a toggle output" do
      before do
        cia.control_a.output = true
        cia.control_a.out_mode = true
        cia.control_a.start = true
        cia.timer_a = 0x01
        cia.timer_a_latch = 0x05
        3.times { cia.cycle! } # underflow toggles PB6 low
      end

      it "sets the toggle output high when the timer is started" do
        cia.poke(0xdc0e, 0b00000110) # stop
        cia.poke(0xdc0e, 0b00000111) # start + output + toggle
        expect(cia[0xdc01][6]).to eq(1)
      end

      it "leaves the toggle state alone while the timer is running" do
        cia.poke(0xdc0e, 0b00000111) # start while already started
        expect(cia[0xdc01][6]).to eq(0)
      end
    end
  end

  describe "keyboard peripheral" do
    subject(:cia) { described_class.new(start: 0xdc00, peripheral: keyboard) }

    let(:keyboard) { Badline::Keyboard.new }

    it "returns the port A register when reading port A" do
      cia.poke(0xdc00, 0xfe)
      expect(cia[0xdc00]).to eq(0xfe)
    end

    it "scans the keyboard matrix when reading port B" do
      keyboard.press(:a)
      cia.poke(0xdc00, 0xfd) # select row 1 (low)
      expect(cia[0xdc01]).to eq(0xff - 0b100)
    end

    it "reads all rows high when no keys are pressed" do
      cia.poke(0xdc00, 0x00)
      expect(cia[0xdc01]).to eq(0xff)
    end
  end

  describe "joystick 2 on port A" do
    subject(:cia) { described_class.new(start: 0xdc00, peripheral:) }

    let(:peripheral) do
      Badline::ControlPorts.new(keyboard: Badline::Keyboard.new, joystick1: Badline::Joystick.new, joystick2:)
    end
    let(:joystick2) { Badline::Joystick.new }

    it "shows a pressed switch through the default output port" do
      joystick2.press(:up)
      cia.poke(0xdc02, 0xff) # DDRA as the KERNAL leaves it (all outputs)
      cia.poke(0xdc00, 0xff) # idle high, as a PEEK(56320) would see
      expect(cia[0xdc00]).to eq(0b11111110)
    end

    it "shows a pressed switch when port A is set to input" do
      joystick2.press(:up)
      cia.poke(0xdc02, 0x00) # port A all inputs
      expect(cia[0xdc00]).to eq(0b11111110)
    end

    it "still reflects a line the CPU drives low" do
      joystick2.press(:fire) # bit 4
      cia.poke(0xdc02, 0xff)
      cia.poke(0xdc00, 0b11111110) # CPU drives bit 0 low
      expect(cia[0xdc00]).to eq(0b11101110)
    end
  end

  describe "joystick 1 on port B" do
    subject(:cia) { described_class.new(start: 0xdc00, peripheral:) }

    let(:peripheral) do
      Badline::ControlPorts.new(keyboard:, joystick1:, joystick2: Badline::Joystick.new)
    end
    let(:keyboard) { Badline::Keyboard.new }
    let(:joystick1) { Badline::Joystick.new }

    it "shows a pressed switch through port B" do
      joystick1.press(:right) # bit 3
      expect(cia[0xdc01]).to eq(0b11110111)
    end

    it "pulls the matrix row of a key sharing the column low" do
      keyboard.press(:g) # row 3, column 2
      joystick1.press(:left) # bit 2
      cia.poke(0xdc02, 0x00) # port A all inputs, as a reverse scan leaves it
      expect(cia[0xdc00]).to eq(0b11110111)
    end
  end

  describe "reverse keyboard scan" do
    subject(:cia) { described_class.new(start: 0xdc00, peripheral: keyboard) }

    let(:keyboard) { Badline::Keyboard.new }

    before do
      cia.poke(0xdc02, 0x00) # port A all inputs
      cia.poke(0xdc03, 0xff) # port B all outputs
    end

    it "reports the row of a key in the driven column" do
      keyboard.press(:a) # row 1, column 2
      cia.poke(0xdc01, 0b11111011) # drive column 2 low
      expect(cia[0xdc00]).to eq(0b11111101)
    end

    it "ignores the stale port A register while port A is an input" do
      keyboard.press(:a)
      cia.poke(0xdc00, 0b11111101) # left over from a forward scan
      cia.poke(0xdc01, 0b11111110) # drive column 0 low
      expect(cia[0xdc00]).to eq(0xff)
    end
  end

  describe "data direction masking" do
    it "reads output bits from the data register" do
      cia.poke(0xdc02, 0xff) # all outputs
      cia.poke(0xdc00, 0x5a)
      expect(cia[0xdc00]).to eq(0x5a)
    end

    it "reads input bits as high when nothing drives the pins" do
      cia.poke(0xdc03, 0x00) # all inputs
      cia.poke(0xdc01, 0x00)
      expect(cia[0xdc01]).to eq(0xff)
    end

    it "combines output register and input pins per the direction mask" do
      cia.poke(0xdc02, 0x0f) # low nibble output, high nibble input
      cia.poke(0xdc00, 0x33)
      expect(cia[0xdc00]).to eq(0xf3)
    end
  end
end
