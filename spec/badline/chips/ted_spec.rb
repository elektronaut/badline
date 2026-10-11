# frozen_string_literal: true

require "spec_helper"
require "badline/plus4"

describe Badline::Chips::TED do
  subject(:ted) { described_class.new }

  # The CPU cycles the TED gives in the next +count+ cycles.
  def cpu_cycles(count)
    Array.new(count) do
      ted.cycle!
      ted.cpu_slots
    end.sum
  end

  # Runs to the start of +line+, column 47, where the line count steps.
  def run_to_line(line)
    ted.cycle! until ted.line == line
  end

  describe "the beam" do
    it "steps the line once every 57 cycles" do
      run_to_line(1)
      57.times { ted.cycle! }
      expect([ted.line, ted.column]).to eq([2, 47])
    end

    it "runs 312 lines a frame on PAL" do
      run_to_line(311)
      57.times { ted.cycle! }
      expect(ted.line).to eq(0)
    end

    it "runs 262 lines a frame with $FF07 bit 6 set" do
      ted.poke(0xff07, 0x48)
      run_to_line(261)
      57.times { ted.cycle! }
      expect(ted.line).to eq(0)
    end

    it "reads the line from $FF1C and $FF1D" do
      run_to_line(300)
      expect([ted.peek(0xff1c), ted.peek(0xff1d)]).to eq([0xff, 300 - 256])
    end

    it "stands still while $FF07 bit 5 freezes it" do
      ted.poke(0xff07, 0x20)
      100.times { ted.cycle! }
      expect([ted.line, ted.column]).to eq([0, 0])
    end
  end

  describe "the CPU's clock" do
    before { run_to_line(1) }

    it "runs the CPU 109 times a line in the border" do
      expect(cpu_cycles(57)).to eq(109)
    end

    context "with the display on" do
      before { ted.poke(0xff06, 0x1b) }

      it "runs the CPU 64 times a display line" do
        run_to_line(5)
        expect(cpu_cycles(57)).to eq(64)
      end

      it "runs it 24 times a DMA line" do
        run_to_line(3)
        expect(cpu_cycles(57)).to eq(24)
      end

      it "takes the bus for the character pointers on a row's first line" do
        run_to_line(4)
        expect(cpu_cycles(57)).to eq(24)
      end

      it "runs it 109 times a line below line 203" do
        run_to_line(204)
        expect(cpu_cycles(57)).to eq(109)
      end

      it "holds BA low from 3 cycles before the DMA" do
        run_to_line(3)
        ted.cycle! until ted.column == 51
        expect([ted.ba_low?, ted.cpu_slots]).to eq([true, 1])
      end
    end

    it "runs the CPU once a cycle with $FF13 bit 1 set" do
      ted.poke(0xff13, 0x02)
      expect(cpu_cycles(57)).to eq(57)
    end
  end

  describe "the timers" do
    it "counts timer 1 down from its value once it has both bytes" do
      ted.poke(0xff00, 0x10)
      ted.poke(0xff01, 0x00)
      5.times { ted.cycle! }
      expect(ted.peek(0xff00)).to eq(0x0b)
    end

    it "holds a timer whose low byte alone was written" do
      ted.poke(0xff02, 0x10)
      5.times { ted.cycle! }
      expect(ted.peek(0xff02)).to eq(0x10)
    end

    it "raises timer 1's flag as it counts down to zero" do
      ted.poke(0xff00, 0x03)
      ted.poke(0xff01, 0x00)
      3.times { ted.cycle! }
      expect(ted.interrupt_flags & 0x08).to eq(0x08)
    end

    it "reloads timer 1 from what was written to it" do
      ted.poke(0xff00, 0x03)
      ted.poke(0xff01, 0x00)
      4.times { ted.cycle! }
      expect(ted.peek(0xff00)).to eq(0x03)
    end

    it "rolls timer 2 over to $FFFF" do
      ted.poke(0xff02, 0x01)
      ted.poke(0xff03, 0x00)
      2.times { ted.cycle! }
      expect([ted.peek(0xff02), ted.peek(0xff03)]).to eq([0xff, 0xff])
    end
  end

  describe "the interrupt" do
    before do
      ted.poke(0xff0b, 2)
      ted.poke(0xff0a, 0x02)
    end

    it "pulls IRQ once the raster reaches the compared line" do
      run_to_line(2)
      expect([ted.irq?, ted.peek(0xff09)]).to eq([true, 0xa3])
    end

    it "lets go once the flag is cleared" do
      run_to_line(2)
      ted.poke(0xff09, 0x02)
      expect(ted.irq?).to be(false)
    end

    it "keeps a masked flag from pulling IRQ" do
      ted.poke(0xff0a, 0x00)
      run_to_line(2)
      expect([ted.irq?, ted.interrupt_flags]).to eq([false, 0x02])
    end

    it "compares bit 8 of the line from $FF0A bit 0" do
      ted.poke(0xff0a, 0x03)
      run_to_line(2)
      expect(ted.irq?).to be(false)
    end
  end

  describe "the keyboard latch" do
    let(:port) { instance_double(Badline::Plus4::KeyboardPort, latch: 0xfb) }

    before { ted.keyboard_port = port }

    it "latches the keyboard port's inputs on a write and reads them back" do
      ted.poke(0xff08, 0xfe)
      expect(ted.peek(0xff08)).to eq(0xfb)
    end
  end

  it "reads in $FF13 bit 0 whether the CPU sees ROM" do
    ted.poke(0xff13, 0xd0)
    ted.rom_selected = false
    expect(ted.peek(0xff13)).to eq(0xd0)
  end

  it "reads the horizontal position's top 8 bits from $FF1E" do
    10.times { ted.cycle! }
    expect(ted.peek(0xff1e)).to eq(40)
  end
end
