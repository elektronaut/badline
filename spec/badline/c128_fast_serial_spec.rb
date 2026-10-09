# frozen_string_literal: true

require "spec_helper"
require "badline/c128"
require_relative "../support/drive1541_rom"

describe Badline::C128 do
  describe "fast serial" do
    subject(:machine) { described_class.new(mode: :c128) }

    let(:bus) { machine.iec_bus }
    let(:srq) { Badline::IECBus::SRQ }

    # CIA 1 shifting $A5 out from timer A at latch 4, and MCR's FSDIR at
    # +fsdir+.
    def send_byte(fsdir)
      machine.mmu.poke(0xd505, fsdir ? 0x09 : 0x01)
      [[0xdc04, 4], [0xdc05, 0], [0xdc0e, 0x51], [0xdc0c, 0xa5]].each { |addr, value| machine.cia1.poke(addr, value) }
    end

    # How many times SRQ goes low over +cycles+ cycles.
    def srq_pulses(cycles)
      levels = Array.new(cycles) do
        machine.cycle!
        bus.low_lines & srq
      end
      levels.chunk_while { |a, b| a == b }.count { |run| run.first == srq }
    end

    it "clocks CIA 1's byte out on SRQ with FSDIR out" do
      send_byte(true)
      expect(srq_pulses(200)).to eq(8)
    end

    it "leaves SRQ alone with FSDIR in" do
      send_byte(false)
      expect(srq_pulses(200)).to eq(0)
    end

    it "hears a drive pulling SRQ on CIA 1's CNT with FSDIR in" do
      drive = Badline::Drive1541.new(rom: Drive1541ROM.stub)
      machine.attach_drive1541(drive)
      allow(drive).to receive(:serial_output).and_return(Badline::IECBus::DRIVE_FAST_SRQ)
      bus.drives_fast_moved!
      expect(machine.cia1.serial.cnt_in).to be(false)
    end

    it "finds a 1571 that answers in burst mode", :slow do
      machine.attach_drive1571(Badline::Drive1571.new)
      machine.on_init { machine.type_text("open1,8,15:close1\r") }
      machine.run_cycles(4_000_000)
      expect(machine.ram.peek(0x0a1c) & 0x40).to eq(0x40)
    end

    it "finds a 1541 that doesn't", :slow do
      machine.attach_drive1541(Badline::Drive1541.new)
      machine.on_init { machine.type_text("open1,8,15:close1\r") }
      machine.run_cycles(4_000_000)
      expect(machine.ram.peek(0x0a1c) & 0x40).to eq(0)
    end
  end
end
