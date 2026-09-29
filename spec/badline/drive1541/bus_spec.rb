# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/drive1541_rom"

describe Badline::Drive1541::Bus do
  subject(:bus) { described_class.new(rom:, via1: serial_via, via2: disk_via) }

  let(:rom) do
    Badline::ROM.new(Array.new(0x4000) { |i| i & 0xff }, length: 0x4000, start: 0xc000)
  end
  let(:serial_via) { Badline::VIA.new(start: 0x1800) }
  let(:disk_via) { Badline::VIA.new(start: 0x1c00) }

  describe "RAM" do
    it "holds 2 KB from $0000" do
      bus.poke(0x07ff, 0x5a)
      expect(bus.ram.peek(0x07ff)).to eq(0x5a)
    end
  end

  # Pinned by VICE-testprogs drive/openbus, which passes on a real 1541.
  describe "open bus at $0800-$17FF" do
    it "reads the last byte on the data bus" do
      bus.poke(0x0123, 0x42)
      bus.peek(0x0123)
      expect([0x0923, 0x1123].map { |a| bus.peek(a) }).to eq([0x42, 0x42])
    end

    it "reads back the last byte written" do
      bus.poke(0x1000, 0x5c)
      expect(bus.peek(0x0800)).to eq(0x5c)
    end

    it "doesn't mirror RAM" do
      bus.poke(0x0456, 0x99)
      bus.peek(0xc0aa)
      expect(bus.peek(0x0c56)).to eq(0xaa)
    end

    it "ignores writes" do
      bus.poke(0x1456, 0x99)
      expect(bus.ram.peek(0x0456)).to eq(0)
    end

    it "reads the high byte of LDA abs's address" do
      cpu = Badline::CPU.new(bus)
      bus.ram.write(0x0300, [0xad, 0x23, 0x0c]) # LDA $0C23
      cpu.program_counter = 0x0300
      cpu.step!
      expect(cpu.a).to eq(0x0c)
    end

    it "reads what the dummy read of a page-crossing LDA abs,X found" do
      cpu = Badline::CPU.new(bus)
      bus.ram.write(0x0700, [0xa2, 0x01, 0xbd, 0xff, 0x07]) # LDX #$01; LDA $07FF,X
      cpu.program_counter = 0x0700 # the dummy read at $0700 finds LDX's opcode
      2.times { cpu.step! }
      expect(cpu.a).to eq(0xa2)
    end
  end

  describe "the VIAs" do
    it "puts VIA 1 at $1800" do
      bus.poke(0x1802, 0x3c)
      expect(serial_via.peek(0x1802)).to eq(0x3c)
    end

    it "puts VIA 2 at $1C00" do
      bus.poke(0x1c03, 0xc3)
      expect(disk_via.peek(0x1c03)).to eq(0xc3)
    end

    it "repeats VIA 1's sixteen registers up to $1BFF" do
      serial_via.poke(0x1803, 0x77)
      expect(bus.peek(0x1bf3)).to eq(0x77)
    end

    it "repeats VIA 2's sixteen registers up to $1FFF" do
      disk_via.poke(0x1c02, 0x66)
      expect(bus.peek(0x1ff2)).to eq(0x66)
    end
  end

  describe "the ROM" do
    it "sits at $C000-$FFFF" do
      expect([0xc000, 0xc0ff, 0xfffc].map { |a| bus.peek(a) }).to eq([0x00, 0xff, 0xfc])
    end

    it "is mirrored at $8000-$BFFF" do
      expect(bus.peek(0x8123)).to eq(0x23)
    end

    it "ignores writes" do
      bus.poke(0xc001, 0xaa)
      expect(bus.peek(0xc001)).to eq(0x01)
    end
  end

  describe "the undecoded A13 and A14" do
    it "repeats RAM at $2000, $4000 and $6000" do
      bus.poke(0x0010, 0x11)
      expect([0x2010, 0x4010, 0x6010].map { |a| bus.peek(a) }).to eq([0x11, 0x11, 0x11])
    end

    it "repeats open bus at $2800, $4800 and $6800" do
      bus.poke(0x0010, 0x11)
      bus.peek(0xc0aa)
      expect([0x2810, 0x4810, 0x7010].map { |a| bus.peek(a) }).to eq([0xaa, 0xaa, 0xaa])
    end

    it "repeats the VIAs at $2000-$7FFF" do
      bus.poke(0x7802, 0x12)
      bus.poke(0x3c02, 0x34)
      expect([serial_via.peek(0x1802), disk_via.peek(0x1c02)]).to eq([0x12, 0x34])
    end
  end
end
