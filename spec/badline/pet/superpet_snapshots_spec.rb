# frozen_string_literal: true

require "spec_helper"

describe Badline::PET::SuperPET do
  describe "snapshots" do
    # A machine with the switch at +cpu+, run part way through its reset.
    def booting(cpu, cycles = 20_001) = described_class.new(cpu:).tap { |machine| machine.run_cycles(cycles) }

    # A machine with the switch at +cpu+ that has had +writes+, address
    # and byte, poked in turn, restored from its snapshot.
    def poked(*writes, cpu: "6502")
      machine = described_class.new(cpu:)
      writes.each_slice(2) { |addr, value| machine.poke(addr, value) }
      machine.snapshot.load
    end

    %w[6502 6809].each do |cpu|
      it "restores one with the CPU switch at #{cpu} that runs on as the saved one" do
        machine = booting(cpu)
        restored = machine.snapshot.load
        [machine, restored].each { |each_machine| each_machine.run_cycles(20_000) }
        expect(restored.snapshot).to eq(machine.snapshot)
      end
    end

    it "adds the board, the ACIA and the 6809 to the 8032's modules" do
      expect(booting("6502", 1).snapshot.sections.map(&:name).last(3)).to eq(%w[BL-SUPERPET BL-ACIA BL-M6809])
    end

    it "builds the loaded machine with the saved one's switches" do
      machine = described_class.new(cpu: "prog", bank_ram: "read")
      restored = machine.snapshot.load
      expect([restored.class, restored.board.cpu_switch, restored.board.ram_switch])
        .to eq([described_class, "prog", "read"])
    end

    it "refuses to restore into one with its switches set otherwise" do
      image = described_class.new(cpu: "6809").snapshot
      expect { described_class.new.restore(image) }
        .to raise_error(Badline::Snapshot::FormatError, /CPU switch at 6809/)
    end

    it "carries the latches and the bank RAM over" do
      restored = poked(0xeffc, 5, 0x9abc, 0x5a, 0xeffc, 0x87, 0xeff8, 0x0b)
      board = restored.board
      expect([board.bank_latch, board.system_latch, board.cells[0x5abc], restored.peek(0x9abc)])
        .to eq([0x87, 0x0b, 0x5a, 0])
    end

    it "lays the empty socket over $9000 as the saved one had it, open to the last byte on the bus" do
      expect(poked(0x9000, 0x5a, 0xeffe, 1).peek(0x9000)).to eq(1)
    end

    it "gives the bus to the CPU the latches pick with the switch at PROG" do
      expect(poked(0xeffc, 0x80, 0xeff8, 0x01, cpu: "prog").m6809_running?).to be(false)
    end

    it "carries the diagnostic sense line over" do
      restored = poked(0xeffc, 0x80, 0xeff8, 0x08)
      restored.pia1.poke(0xe811, 0x04)
      expect(restored.pia1.peek(0xe810) & 0x80).to eq(0)
    end

    it "carries the 6702's registers and a shift still to come over" do
      machine = described_class.new
      machine.poke(0xefe0, 0x00)
      machine.poke(0xefe0, 0x01)
      dongle = machine.snapshot.load.dongle
      expect([dongle.latch, dongle.shift_at - machine.cycles]).to eq([0x01, 1])
    end

    it "carries the ACIA's registers over" do
      acia = poked(0xeff2, 0x6b, 0xeff3, 0x3a).acia
      expect([acia.command, acia.control]).to eq([0x6b, 0x3a])
    end

    it "carries the 6809's registers over" do
      machine = booting("6809", 5_000)
      expect(machine.snapshot.load.m6809.inspect).to eq(machine.m6809.inspect)
    end

    it "settles the 6809 on its instruction boundary" do
      machine = booting("6809", 5_001)
      machine.snapshot
      expect(machine.m6809.boundary?).to be(true)
    end
  end
end
