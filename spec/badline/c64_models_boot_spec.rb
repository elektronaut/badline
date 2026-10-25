# frozen_string_literal: true

require "spec_helper"
require "digest"
require_relative "../support/taken_once"

# The PET 64, the C64GS and the MAX Machine with nothing attached, checked
# against x64sc 3.10's same models (-default -model <name>
# -raminitrandomchance 0), dumped from its monitor at the same instruction.
# x64sc's clock reads one cycle more than badline's at that instruction.
describe Badline::C64 do
  # The machine at the first instruction at `address` after `cycles`.
  def booted(model, cycles, address)
    TakenOnce.fetch([:c64_model_checkpoint, model]) do
      machine = Badline::Machine.build(:c64, model:)
      machine.run_cycles(cycles)
      cpu = machine.cpu
      machine.run_until(4_000_000) { cpu.boundary? && cpu.program_counter == address }
      machine
    end
  end

  def ram_digest(machine) = Digest::SHA256.hexdigest((2..0xffff).map { |address| machine.ram.peek(address) }.pack("C*"))

  def screen_line(machine, row)
    (0...40).map { |column| machine.ram.peek(0x0400 + (row * 40) + column) & 0x7f }
            .map { |code| code < 0x20 ? (code + 0x40).chr : code.chr }.join.rstrip
  end

  describe "the PET 64 at BASIC's first wait for a key, $E5CD", :slow do
    let(:machine) { booted("pet64", 2_100_000, 0xe5cd) }

    it "gets there when x64sc does" do
      expect(machine.cycles).to eq(2_124_032)
    end

    it "shows its banner" do
      expect([1, 4].map { |row| screen_line(machine, row) }).to eq(["  **** COMMODORE 4064  BASIC V2.0 ****", "READY."])
    end

    it "has x64sc's RAM" do
      expect(ram_digest(machine)).to eq("46638cd4f5c49d7d9c9266d3fca2fc9174ff0f341e0e1d8f674eb64805359cbe")
    end
  end

  describe "the C64GS with no cartridge, at its third wait for the frame, $F8C9", :slow do
    let(:machine) { booted("c64gs", 200_000, 0xf8c9) }

    it "gets there when x64sc does" do
      expect(machine.cycles).to eq(212_692)
    end

    it "shows its banner" do
      expect(screen_line(machine, 3)).to eq("         COMMODORE C64 GAMES SYSTEM")
    end

    it "has x64sc's RAM" do
      expect(ram_digest(machine)).to eq("73048031b1b9bc63496674bb5aaa2c8a305220f5ea02efa4a515320d1b17c63d")
    end

    it "has x64sc's sprites" do
      expect((0xd000..0xd01f).map { |address| machine.peek(address) }.values_at(0..16, 21, 23, 27..29))
        .to eq([0xe0, 0x7e, 0xe0, 0x7e, 0x43, 0x43, 0x94, 0x64, 0x90, 0x82, 0x60, 0x82, 0xe0, 0x7e, 0xac, 0xa7,
                0x00, 0xbe, 0x00, 0x00, 0x04, 0x73])
    end
  end

  describe "the MAX Machine with no cartridge" do
    let(:machine) { Badline::Machine.build(:c64, model: "ultimax").tap { |max| max.run_cycles(300) } }

    it "jams the CPU on the empty bus, as x64sc does" do
      expect(machine.cpu.jammed?).to be(true)
    end

    it "leaves the screen blanked" do
      expect([0xd011, 0xd016, 0xd018, 0xd020].map { |address| machine.peek(address) }).to eq([0x00, 0xc0, 0x01, 0xf0])
    end
  end
end
