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

  describe "the FLAG pin" do
    it "raises the flag bit on a falling edge" do
      cia.flag!
      expect(cia.interrupt_status.flag?).to be(true)
    end

    it "clears the flag bit when the status register is read" do
      cia.flag!
      cia.peek(0xdc0d)
      expect(cia.interrupt_status.flag?).to be(false)
    end

    it "leaves the interrupt line alone while the flag is masked" do
      cia.flag!
      cia.cycle!
      expect(cia).not_to be_interrupted
    end

    it "pulls the interrupt line when the flag is enabled" do
      cia.poke(0xdc0d, 0x90)
      cia.flag!
      cia.cycle!
      expect(cia).to be_interrupted
    end
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

  describe "PB4 pulled low by a peripheral (light pen line)" do
    subject(:cia) { described_class.new(start: 0xdc00, peripheral: ports) }

    let(:joystick1) { Badline::Joystick.new }
    let(:ports) do
      Badline::ControlPorts.new(keyboard: Badline::Keyboard.new, joystick1:,
                                joystick2: Badline::Joystick.new)
    end
    let(:edges) { [] }

    before { cia.on_port_b4_change { |high| edges << high } }

    it "reports the fall when joystick 1 fires" do
      joystick1.press(:fire)
      cia.cycle!
      expect(edges).to eq([false])
    end

    it "reports the rise when the button is let go" do
      joystick1.press(:fire)
      cia.cycle!
      joystick1.release(:fire)
      cia.cycle!
      expect(edges).to eq([false, true])
    end

    it "reports one edge while the button is held" do
      joystick1.press(:fire)
      3.times { cia.cycle! }
      expect(edges).to eq([false])
    end

    it "stays high when another joystick line falls" do
      joystick1.press(:up)
      cia.cycle!
      expect(edges).to be_empty
    end

    it "stays low once the register drives PB4 low too" do
      joystick1.press(:fire)
      cia.poke(0xdc03, 0x10)
      cia.poke(0xdc01, 0x00)
      expect(edges).to eq([false])
    end
  end

  describe "time of day clock" do
    before { cia.poke(0xdc0e, 0x80) } # divide the 50 Hz TOD pin by five

    def advance_one_tenth
      98_525.times { cia.cycle! }
    end

    # The clock is stopped at power-on and starts on a write to tenths.
    def start_clock
      cia.poke(0xdc08, 0x00)
    end

    context "when first powered on" do
      specify { expect(cia[0xdc0b]).to eq(0x01) }
      specify { expect(cia[0xdc0a]).to eq(0x00) }
      specify { expect(cia[0xdc09]).to eq(0x00) }
      specify { expect(cia[0xdc08]).to eq(0x00) }
    end

    it "routes register writes to the clock" do
      cia.poke(0xdc09, 0x31)
      expect(cia[0xdc09]).to eq(0x31)
    end

    it "advances a tenth after clock_hz/10 cycles" do
      start_clock
      advance_one_tenth
      expect(cia[0xdc08]).to eq(0x01)
    end

    it "runs slow when CRA selects 60 Hz" do
      cia.poke(0xdc0e, 0x00)
      start_clock
      advance_one_tenth
      expect(cia[0xdc08]).to eq(0x00)
    end

    context "with the alarm armed" do
      before do
        cia.interrupt_control.alarm = true
        cia.control_b.alarm = true
        cia.poke(0xdc08, 0x01)
        cia.poke(0xdc09, 0x00)
        cia.poke(0xdc0a, 0x00)
        cia.poke(0xdc0b, 0x01)
        cia.control_b.alarm = false
        start_clock
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

  # Pinned by CIA/dd0dtest/dd0dtest (tests 0c, 0d, 0e and 11). The flag
  # rises on cycle 3 and IR on cycle 4.
  describe "the 6526 interrupt acknowledge" do
    before do
      cia.control_a.start = true
      cia.timer_a = 0x01
      cia.timer_a_latch = 0xff
      cia.interrupt_control.timer_a = true
    end

    context "when IR is read" do
      before do
        4.times { cia.cycle! }
        cia.peek(0xdc0d)
        cia.cycle!
      end

      it "releases the interrupt line at once" do
        expect(cia.interrupted?).to be(false)
      end

      it "still reads IR on the next cycle" do
        expect(cia[0xdc0d]).to eq(0x80)
      end

      it "clears IR the cycle after that" do
        cia.cycle!
        expect(cia[0xdc0d]).to eq(0x00)
      end
    end

    context "when the ICR is read on the cycle the flag rises" do
      before do
        3.times { cia.cycle! }
        cia.peek(0xdc0d)
        cia.cycle!
      end

      it "never asserts the interrupt line" do
        expect(cia.interrupted?).to be(false)
      end

      it "reads IR on the next cycle" do
        expect(cia[0xdc0d]).to eq(0x80)
      end
    end

    context "when the source is masked on the flag cycle" do
      def mask_on_flag_cycle(read_at:)
        3.times do |cycle|
          cia.cycle!
          cia.peek(0xdc0d) if cycle + 1 == read_at
        end
        cia.poke(0xdc0d, 0x01)
        cia.cycle!
      end

      it "asserts the interrupt line anyway" do
        mask_on_flag_cycle(read_at: nil)
        expect(cia.interrupted?).to be(true)
      end

      it "cancels the assert while a read two cycles back acknowledges" do
        mask_on_flag_cycle(read_at: 1)
        expect(cia.interrupted?).to be(false)
      end
    end
  end

  # Pinned by CIA/ciavarious/cia3 (tests K and L) and cia-timer-oldcias.
  # The flag rises on cycle 3.
  describe "the 6526 timer B bug" do
    before do
      cia.control_b.start = true
      cia.timer_b = 0x01
      cia.timer_b_latch = 0xff
    end

    def read_then_underflow(read_at:)
      3.times do |cycle|
        cia.peek(0xdc0d) if cycle + 1 == read_at
        cia.cycle!
      end
    end

    it "raises the flag when the ICR was read on the cycle before" do
      read_then_underflow(read_at: 3)
      expect(cia.interrupt_status.timer_b?).to be(true)
    end

    it "drops the flag unseen on the next read" do
      read_then_underflow(read_at: 3)
      expect(cia[0xdc0d]).to eq(0x00)
    end

    it "keeps the flag when the read came earlier" do
      read_then_underflow(read_at: 2)
      expect(cia[0xdc0d]).to eq(0x02)
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

    context "when underflowing" do
      before { 254.times { cia.cycle! } }

      specify { expect(cia.timer_a).to eq(0x43) }
      specify { expect(cia.interrupt_status.timer_a?).to be(true) }
      specify { expect(cia.interrupted?).to be(false) }
      specify { expect(cia.control_a.start?).to be(true) }
    end

    context "when a cycle has passed after underflowing" do
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

      it "copies the latch into the counter two ticks after the write" do
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

    context "when underflowing" do
      before { 254.times { cia.cycle! } }

      specify { expect(cia.timer_b).to eq(0x43) }
      specify { expect(cia.interrupt_status.timer_b?).to be(true) }
      specify { expect(cia.interrupted?).to be(false) }
      specify { expect(cia.control_b.start?).to be(true) }
    end

    context "when a cycle has passed after underflowing" do
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
        2.times { cia.cycle! } # φ2 pulses drain out of the pipeline
        cia.timer_b = 0x05
        cia.control_a.start = true
        cia.timer_a = 0x02
        cia.timer_a_latch = 0x02
      end

      it "decrements two cycles after timer A underflows" do
        6.times { cia.cycle! } # timer A 2 -> 1 -> 0, then timer B's pipeline
        expect(cia.timer_b).to eq(0x04)
      end

      it "does not decrement on the underflow cycle itself" do
        5.times { cia.cycle! } # timer A underflows on the fourth
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

  describe "the CNT line" do
    def pulse_cnt(count = 1)
      count.times do
        cia.serial.cnt_in = false
        2.times { cia.cycle! }
        cia.serial.cnt_in = true
        4.times { cia.cycle! } # the count pipeline is two stages deep
      end
    end

    it "floats high with nothing on the user port" do
      expect(cia.serial.cnt).to be(true)
    end

    it "clocks timer A when CRA selects CNT" do
      cia.poke(0xdc04, 0x00)
      cia.poke(0xdc05, 0x10)
      cia.poke(0xdc0e, 0x21)
      pulse_cnt(5)
      expect(cia.timer_a).to eq(0x1000 - 5)
    end

    it "leaves timer A alone while CNT is idle" do
      cia.poke(0xdc04, 0x00)
      cia.poke(0xdc05, 0x10)
      cia.poke(0xdc0e, 0x21)
      10.times { cia.cycle! }
      expect(cia.timer_a).to eq(0x1000)
    end

    it "clocks timer B when CRB selects CNT" do
      cia.poke(0xdc06, 0x00)
      cia.poke(0xdc07, 0x10)
      cia.poke(0xdc0f, 0x21)
      pulse_cnt(5)
      expect(cia.timer_b).to eq(0x1000 - 5)
    end

    context "when timer B counts timer A underflows gated by CNT" do
      before do
        cia.poke(0xdc04, 0x02)
        cia.poke(0xdc05, 0x00)
        cia.poke(0xdc06, 0x00)
        cia.poke(0xdc07, 0x10)
        cia.poke(0xdc0e, 0x01)
        cia.poke(0xdc0f, 0x61)
      end

      it "counts while CNT is high" do
        100.times { cia.cycle! }
        expect(cia.timer_b).to be < 0x1000
      end

      it "stops while CNT is low" do
        cia.serial.cnt_in = false
        100.times { cia.cycle! }
        expect(cia.timer_b).to eq(0x1000)
      end
    end

    describe "shifting the serial port in" do
      it "reads the idle-high SP line as ones" do
        pulse_cnt(8)
        expect(cia[0xdc0c]).to eq(0xff)
      end

      it "shifts SP in most significant bit first" do
        [1, 0, 1, 0, 0, 1, 0, 1].each do |bit|
          cia.serial.sp_in = bit == 1
          pulse_cnt
        end
        expect(cia[0xdc0c]).to eq(0xa5)
      end

      it "raises the serial flag once the byte has arrived" do
        pulse_cnt(8)
        expect(cia.interrupt_status.serial?).to be(true)
      end

      it "does not raise the serial flag before the eighth bit" do
        pulse_cnt(7)
        expect(cia.interrupt_status.serial?).to be(false)
      end
    end
  end

  describe "the serial port in output mode" do
    # A timer A latch of 9 underflows every tenth cycle, so CNT spends ten
    # cycles low with each bit on SP and ten high again.
    let(:period) { 10 }

    before do
      cia.poke(0xdc0d, 0x88) # unmask the serial interrupt
      cia.poke(0xdc04, 0x09)
      cia.poke(0xdc05, 0x00)
      cia.poke(0xdc0e, 0x41) # serial output, timer A started
      cia.poke(0xdc0c, 0xa5)
    end

    # The transmitter idles until the first underflow pulls CNT low.
    def advance_to_first_bit
      cia.cycle! while cia.serial.cnt
    end

    # CNT falls again as each further bit is put on SP.
    def advance_to_last_bit
      advance_to_first_bit
      7.times do
        cia.cycle! until cia.serial.cnt
        cia.cycle! while cia.serial.cnt
      end
    end

    def cnt_levels(count)
      count.times.map do
        cia.cycle!
        cia.serial.cnt
      end
    end

    it "reads back the byte that was written" do
      expect(cia[0xdc0c]).to eq(0xa5)
    end

    it "does not drive CNT before the first underflow" do
      expect(cia.serial.cnt).to be(true)
    end

    it "toggles CNT at half the timer A underflow rate" do
      advance_to_first_bit
      expect(cnt_levels(2 * period).count { |high| high }).to eq(period)
    end

    it "puts the most significant bit on SP first" do
      advance_to_first_bit
      expect(cia.serial.sp_out).to be(true)
    end

    # Pinned by cia-sdr-delay and the single-baud cia?-sdr-icr rows.
    it "raises the serial flag four cycles after the eighth bit reaches SP" do
      advance_to_last_bit
      4.times { cia.cycle! }
      expect(cia.interrupt_status.serial?).to be(true)
    end

    it "does not raise the serial flag before those four cycles are up" do
      advance_to_last_bit
      3.times { cia.cycle! }
      expect(cia.interrupt_status.serial?).to be(false)
    end

    it "raises the serial flag before CNT rises over that bit" do
      advance_to_last_bit
      4.times { cia.cycle! }
      expect(cia.serial.cnt).to be(false)
    end

    it "leaves CNT high once the byte has gone out" do
      advance_to_last_bit
      period.times { cia.cycle! }
      expect(cia.serial.cnt).to be(true)
    end

    # A byte waiting in the data register goes out on the underflow after
    # the eighth bit reaches SP, so CNT stays low between the two bytes.
    # Pinned by cia-sdr-load.
    context "with a second byte waiting" do
      before do
        advance_to_first_bit
        cia.poke(0xdc0c, 0x00)
        advance_to_last_bit
      end

      it "keeps CNT low into the next byte" do
        expect(cnt_levels(period + 5)).to all(be(false))
      end

      it "puts the next byte's first bit on SP" do
        (period + 1).times { cia.cycle! }
        expect(cia.serial.sp_out).to be(false)
      end
    end

    # Taking the port back as an output resets the shift register, which
    # abandons the bit it was halfway through and counts that byte as gone.
    # Pinned by the single-baud cia?-sdr-icr rows and the test2 sweeps.
    context "when the shift register is reset mid-byte" do
      def reset_after(cycles)
        advance_to_first_bit
        cycles.times { cia.cycle! }
        cia.poke(0xdc0e, 0x00) # stop timer A, hand the port back as input
        cia.peek(0xdc0d)       # clear the ICR
        cia.poke(0xdc0e, 0x41)
      end

      it "raises the serial flag when a bit was still on SP" do
        reset_after(1)
        expect(cia.interrupt_status.serial?).to be(true)
      end

      it "leaves it alone when CNT had already risen" do
        reset_after(2 * period)
        expect(cia.interrupt_status.serial?).to be(false)
      end
    end

    # Handing the port over as an input tears the transmission down, and
    # counts the byte as gone once the register has reported itself busy.
    # Pinned by cia1-sdr-icr-test2-0_7f and cia2-sdr-icr-test2-0_7f.
    context "when the port is handed over as an input mid-byte" do
      def switch_to_input_after(cycles)
        advance_to_first_bit
        cycles.times { cia.cycle! }
        cia.peek(0xdc0d)       # clear the ICR
        cia.poke(0xdc0e, 0x01) # input, timer A still running
      end

      it "raises the serial flag four cycles after the first bit" do
        switch_to_input_after(4)
        expect(cia.interrupt_status.serial?).to be(true)
      end

      it "leaves it alone before then" do
        switch_to_input_after(3)
        expect(cia.interrupt_status.serial?).to be(false)
      end
    end

    # A zero latch holds the underflow line asserted rather than pulsing
    # it, and the shift register needs an edge for every half-step.
    # Pinned by the cia?-sdr-icr-0 rows.
    context "with a zero timer A latch" do
      before do
        cia.poke(0xdc04, 0x00)
        cia.poke(0xdc0e, 0x51) # force the new latch in
        cia.poke(0xdc0c, 0xa5)
        advance_to_first_bit
      end

      it "puts the first bit on SP" do
        expect(cia.serial.sp_out).to be(true)
      end

      it "never raises the serial flag" do
        1000.times { cia.cycle! }
        expect(cia.interrupt_status.serial?).to be(false)
      end

      it "leaves CNT low for good" do
        1000.times { cia.cycle! }
        expect(cia.serial.cnt).to be(false)
      end
    end
  end
end
