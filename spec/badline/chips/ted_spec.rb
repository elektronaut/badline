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
    # Pinned by the TED datasheet's horizontal decode table, column 47;
    # xplus4 steps about 3 cycles later (doc/pinned-behaviour.md).
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

      it "takes no pointers on line 0 with a scroll of 7, with no attributes before it" do
        ted.poke(0xff06, 0x1f)
        run_to_line(2)
        run_to_line(0)
        expect(cpu_cycles(57)).to eq(64)
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

  describe "the fetches" do
    subject(:ted) { machine.ted }

    let(:machine) { Badline::Plus4.new }
    let(:ram) { machine.ram }
    let(:kernal) { Badline::ROM.read("plus4/kernal-pal.rom") }

    # Runs to +column+ of +line+.
    def run_to(line, column)
      ted.cycle! until ted.line == line && ted.column == column
    end

    before do
      ted.poke(0xff14, 0x08)
      ted.poke(0xff13, 0xd0)
      ted.poke(0xff12, 0x04)
      ram.poke(0x0800, 0x71)
      ram.poke(0x0c00, 0x01)
      ted.poke(0xff06, 0x1b)
    end

    it "fetches a row's attributes on the line before it and its pointers on its first line" do
      run_to(4, 55)
      expect([ted.attributes[0], ted.pointers[0]]).to eq([0x71, 0x01])
    end

    it "keeps the row before on its own attributes to its last line" do
      ram.poke(0x0828, 0x25)
      run_to(11, 55)
      expect(ted.attributes[0]).to eq(0x71)
    end

    it "fetches a character's pattern from the character base with the row's line" do
      run_to(6, 56)
      expect(ted.patterns[0]).to eq(kernal[0x1000 + 8 + 2])
    end

    it "leaves the pattern byte on the bus" do
      run_to(6, 55)
      expect(machine.bus.data).to eq(kernal[0x1000 + 8 + 2])
    end

    it "takes the pointer's bit 7 as reverse while $FF07 bit 7 is clear" do
      ram.poke(0x0c00, 0x81)
      run_to(5, 56)
      expect(ted.patterns[0]).to eq(kernal[0x1000 + 8 + 1])
    end

    it "fetches 256 characters with $FF07 bit 7 set" do
      ted.poke(0xff07, 0x80)
      ram.poke(0x0c00, 0x81)
      run_to(5, 56)
      expect(ted.patterns[0]).to eq(kernal[0x1000 + 0x408 + 1])
    end

    it "fetches from the first 64 characters in extended colour mode" do
      ted.poke(0xff06, 0x5b)
      ram.poke(0x0c00, 0xc1)
      run_to(5, 56)
      expect(ted.patterns[0]).to eq(kernal[0x1000 + 8 + 1])
    end

    it "fetches bitmap bytes from the bitmap base with the character position and the row's line" do
      ted.poke(0xff12, 0x08)
      ted.poke(0xff06, 0x3b)
      ram.poke(0x2000 + (41 * 8) + 3, 0x5a)
      run_to(15, 0)
      expect(ted.patterns[1]).to eq(0x5a)
    end

    # Pinned by xplus4 screenshots of a scroll change mid-row.
    it "fetches the attributes of the row the next pointers read after a row runs long" do
      ram.poke(0x0800 + (13 * 40), 0x25)
      run_to(100, 52)
      ted.poke(0xff06, 0x1c)
      run_to(109, 55)
      expect(ted.attributes[0]).to eq(0x25)
    end

    # Pinned by xplus4 screenshots of a scroll change mid-row.
    it "fetches no pointers on a line whose scroll asks for them after a line without attributes" do
      run_to(101, 52)
      ted.poke(0xff06, 0x1d)
      run_to(102, 56)
      expect(ted.row_line).to eq(2)
    end

    # Pinned by xplus4 screenshots of a scroll change mid-row.
    it "runs the row's line on through a pointer line after a scroll change" do
      run_to(20, 52)
      ted.poke(0xff06, 0x1c)
      run_to(29, 56)
      expect(ted.row_line).to eq(1)
    end

    it "moves the character position on by 40 at the end of a row" do
      run_to(12, 0)
      expect([ted.peek(0xff1a), ted.peek(0xff1b)]).to eq([0xfc, 40])
    end

    it "counts the row's lines in $FF1F" do
      run_to(7, 0)
      expect(ted.peek(0xff1f) & 0x07).to eq(3)
    end

    it "holds the row's line after line 203" do
      run_to(250, 0)
      expect([ted.row_line, ted.char_position]).to eq([7, 1000])
    end

    it "starts the character position over with the frame" do
      ted.poke(0xff1b, 0x55)
      run_to(0, 50)
      expect(ted.char_position).to eq(0)
    end

    # Pinned by xplus4, which counts the blink counter on line 256.
    it "counts frames in the blink counter on line 256" do
      run_to(256, 43)
      expect(ted.peek(0xff1f) >> 3).to eq(0x11)
    end

    it "sets the row's line and the blink counter through $FF1F" do
      ted.poke(0xff1f, 0x2d)
      expect(ted.peek(0xff1f)).to eq(0xad)
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
