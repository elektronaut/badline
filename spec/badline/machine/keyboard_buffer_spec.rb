# frozen_string_literal: true

require "spec_helper"

describe Badline::Machine::KeyboardBuffer do
  let(:computer) { Badline::C64.new }

  describe "#type_text" do
    before { allow(computer).to receive(:on_init).and_yield }

    it "writes PETSCII codes to the keyboard buffer" do
      computer.type_text("lO\"\r")
      computer.cycle!
      expect(computer.ram.read(0x0277, 4)).to eq([0x4c, 0xcf, 0x22, 0x0d])
    end

    it "sets the buffer count" do
      computer.type_text("run\r")
      computer.cycle!
      expect(computer.ram.peek(0xc6)).to eq(4)
    end

    it "fills the buffer to ten characters at a time" do
      computer.type_text("poke 53280,0\r")
      computer.cycle!
      expect(computer.ram.peek(0xc6)).to eq(10)
    end

    it "feeds the remainder once the buffer drains" do
      computer.type_text("poke 53280,0\r")
      2.times { computer.cycle! }
      computer.ram.poke(0xc6, 0)
      computer.cycle!
      expect(computer.ram.read(0x0277, 3)).to eq([0x2c, 0x30, 0x0d])
    end

    it "does not refill a buffer that still has characters" do
      computer.type_text("poke 53280,0\r")
      3.times { computer.cycle! }
      expect(computer.ram.peek(0xc6)).to eq(10)
    end
  end

  # Where each PET editor's keyboard scan stores a key: LDX NDX, then STA
  # KEYD,X.
  {
    "editor1" => [described_class::PET_BASIC1_LAYOUT, 0xe72c, 0xe72f],
    "editor2-n" => [described_class::PET_LAYOUT, 0xe6d6, 0xe6d8],
    "editor4-b" => [described_class::PET_LAYOUT, 0xe538, 0xe53a],
    "editor4-80-b-50hz" => [described_class::PET_LAYOUT, 0xe563, 0xe569]
  }.each do |rom, (layout, load_count, store_key)|
    it "finds the count and the buffer where pet/#{rom} stores a key" do
      editor = Badline::ROM.read("pet/#{rom}.rom")
      count = layout.count > 0xff ? [0xae, layout.count & 0xff, layout.count >> 8] : [0xa6, layout.count]
      code = [editor[load_count - 0xe000, count.length], editor[store_key - 0xe000, 3]]
      expect(code).to eq([count, [0x9d, layout.address & 0xff, layout.address >> 8]])
    end
  end
end
