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
end
