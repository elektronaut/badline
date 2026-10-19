# frozen_string_literal: true

require "spec_helper"
require_relative "../support/taken_once"

# The key sequences and what the display shows after each are the KIM-1
# User Manual's: figure 5.5 enters the sample program of figure 5.4, and
# figure 5.6 single-steps it.
describe Badline::KIM1 do
  subject(:kim) { described_class.new }

  # The sample program of figure 5.4, at $0200.
  let(:sample_program) do
    [0xa9, 0x01, 0x8d, 0x01, 0x17, 0xee, 0x00, 0x17, 0xad, 0x00,
     0x17, 0x49, 0xff, 0x4a, 0xaa, 0xca, 0x10, 0xfd, 0x30, 0xf1]
  end

  def deposit(address, bytes)
    bytes.each_with_index { |byte, offset| kim.poke(address + offset, byte) }
  end

  # Presses the keys and runs on until the monitor has taken them.
  def keys(text)
    kim.type_keys(text)
    kim.run_cycles(1_000) while kim.typing?
    kim.display_text
  end

  # What the display shows after each run of keys in `steps`.
  def displays(steps) = steps.map { |step| keys(step) }

  def stop_vector!
    deposit(0x17fa, [0x00, 0x1c])
  end

  # Runs the program at `address` from the monitor: PC recalls the PC
  # saved at $EF-$F0, and GO starts it.
  def run_from(address)
    deposit(0xef, [address & 0xff, address >> 8])
    keys("PC GO")
  end

  def boot!
    kim.run_cycles(described_class::BOOT_CYCLES)
  end

  it "is the KIM-1 family" do
    expect(kim.family).to eq(:kim1)
  end

  context "when booted" do
    before { boot! }

    it "shows address $0000 and the byte there" do
      expect(kim.display_text).to eq("0000 00")
    end

    # The monitor's SCANDS ($1F1F) and its key scan, AK ($1EFE), run on
    # the 6502 core's cycle counts, which SingleStepTests checks.
    it "scans the six digits every 4,258 cycles" do
      kim.panel.lit_cycles
      kim.run_cycles(4_258 * 10)
      lit = kim.panel.lit_cycles.each_slice(7).map(&:first)
      expect(lit).to eq([6_760, 6_870, 6_760, 6_870, 6_760, 6_570])
    end

    it "takes an address and a byte from the keypad" do
      expect([keys("AD 0200 DA A9"), kim.peek(0x0200)]).to eq(["0200 A9", 0xa9])
    end

    it "goes dark while a program runs" do
      deposit(0x0200, [0x4c, 0x00, 0x02])
      run_from(0x0200)
      kim.run_cycles(30_000)
      expect([kim.display_text, (0x0200..0x0202).cover?(kim.cpu.program_counter)]).to eq(["       ", true])
    end

    it "takes RS and ST as keys too" do
      stop_vector!
      deposit(0x0200, [0x4c, 0x00, 0x02])
      deposit(0xef, [0x00, 0x02])
      expect(displays(["PC GO ST", "RS"])).to eq(["0200 4C", "0200 4C"])
    end

    describe "ST" do
      # LDA #$12, LDX #$34, LDY #$56, then a JMP to itself at $0206.
      before do
        deposit(0x0200, [0xa9, 0x12, 0xa2, 0x34, 0xa0, 0x56, 0x4c, 0x06, 0x02])
        stop_vector!
        run_from(0x0200)
        kim.press_stop
        kim.run_cycles(20_000)
      end

      it "saves the PC, P, SP, A, Y and X at $EF-$F5" do
        expect(Array.new(7) { |offset| kim.peek(0xef + offset) }).to eq([0x06, 0x02, 0x20, 0xff, 0x12, 0x56, 0x34])
      end

      it "shows the PC and the instruction there" do
        expect(kim.display_text).to eq("0206 4C")
      end

      it "leaves RAM alone through RS" do
        kim.press_reset
        boot!
        expect([kim.peek(0xf3), kim.display_text]).to eq([0x12, "0206 4C"])
      end

      it "clears RAM on a power cycle" do
        kim.power_cycle!
        boot!
        expect([kim.peek(0xf3), kim.display_text]).to eq([0x00, "0000 00"])
      end
    end
  end

  describe "U3's PB7" do
    # U3's timer at ÷1 with its interrupt enabled, timing out at once.
    before do
      kim.poke(0x170c, 1)
      kim.run_cycles(3)
    end

    it "pulls IRQ once wired to it" do
      kim.irq_wired = true
      kim.cycle!
      expect(kim.cpu.irq).to be(true)
    end

    it "leaves IRQ alone unwired" do
      kim.cycle!
      expect(kim.cpu.irq).to be(false)
    end
  end

  context "with the TTY/KB jumper fitted" do
    subject(:kim) { described_class.new(tty: true) }

    it "waits for the teletype's RUBOUT with the display dark" do
      kim.run_cycles(Badline::KIM1::Teletype::RUBOUT_DELAY - 500)
      expect([kim.tty?, kim.display_text, (0x1c31..0x1c37).cover?(kim.cpu.program_counter)])
        .to eq([true, "       ", true])
    end
  end

  describe "figure 5.5", :slow do
    # Each step's keys and what the display shows after them. The byte
    # $AD goes in as A and D, since AD names the key.
    let(:steps) do
      [["AD 0200", "0200 00"], ["DA A9", "0200 A9"], ["+ 01", "0201 01"], ["+ 8D", "0202 8D"],
       ["+ 01", "0203 01"], ["+ 17", "0204 17"], ["+ EE", "0205 EE"], ["+ 00", "0206 00"],
       ["+ 17", "0207 17"], ["+ A D", "0208 AD"], ["+ 00", "0209 00"], ["+ 17", "020A 17"],
       ["+ 49", "020B 49"], ["+ FF", "020C FF"], ["+ 4A", "020D 4A"], ["+ AA", "020E AA"],
       ["+ CA", "020F CA"], ["+ 10", "0210 10"], ["+ FD", "0211 FD"], ["+ 30", "0212 30"],
       ["+ F1", "0213 F1"]]
    end

    let(:entered) do
      TakenOnce.fetch("KIM-1 figure 5.5") do
        boot!
        [displays(steps.map(&:first)), Array.new(20) { |offset| kim.peek(0x0200 + offset) }]
      end
    end

    it "shows each address and byte as it is entered" do
      expect(entered.first).to eq(steps.map(&:last))
    end

    it "leaves the program in RAM" do
      expect(entered.last).to eq(sample_program)
    end
  end

  # Pinned by figure 5.6: SST steps the 2-cycle LDA #$01 and TAX one at a
  # time (CPU#single_step).
  describe "figure 5.6", :slow do
    # Each step's keys and what the display shows after them, with the
    # selector switches open: port A's inputs read high.
    let(:steps) do
      [["AD 0200", "0200 A9"], ["GO", "0202 8D"], ["GO", "0205 EE"], ["GO", "0208 AD"],
       ["GO", "020B 49"], ["GO", "020D 4A"], ["GO", "020E AA"],
       ["AD 00F3", "00F3 00"], ["+", "00F4 00"], ["+", "00F5 00"], ["PC", "020E AA"],
       ["GO", "020F CA"], ["AD 00F3", "00F3 00"], ["+", "00F4 00"], ["+", "00F5 00"], ["PC", "020F CA"],
       ["GO", "0210 10"], ["AD 00F5", "00F5 FF"], ["PC", "0210 10"], ["GO", "0212 30"], ["GO", "0205 EE"]]
    end

    it "steps the sample program one instruction at a time" do
      deposit(0x0200, sample_program)
      stop_vector!
      boot!
      kim.sst = true
      expect(displays(steps.map(&:first))).to eq(steps.map(&:last))
    end
  end
end
