# frozen_string_literal: true

require "spec_helper"

RSpec.describe Badline::Computer do
  let(:computer) { described_class.new }

  describe "VIC-II bad line cycle stealing" do
    before do
      computer.vic.poke(0xd011, 0x1b) # DEN=1, RSEL=1, YSCROLL=3
      computer.vic.poke(0xd016, 0x08) # Text mode
    end

    it "allows CPU to execute during non-bad line cycles" do
      initial_cpu_cycles = computer.cpu.cycles

      ((50 * 63) + 20).times { computer.cycle! }

      expect(computer.cpu.cycles).to be > initial_cpu_cycles
    end

    it "prevents CPU execution during VIC DMA cycles" do
      (51 * 63).times { computer.cycle! }
      initial_cpu_cycles = computer.cpu.cycles

      20.times { computer.cycle! }

      # Some cycles were stolen
      expect(computer.cpu.cycles - initial_cpu_cycles).to be < 20
    end
  end

  describe "VIC-II sprite DMA cycle stealing" do
    before do
      computer.vic.poke(0xd011, 0x1b) # DEN=1, RSEL=1, YSCROLL=3
      computer.vic.poke(0xd015, 0x01) # enable sprite 0
      computer.vic.poke(0xd001, 60)   # sprite 0 displays from line 60
    end

    it "steals CPU cycles for an active sprite on a non-bad line" do
      (60 * 63).times { computer.cycle! } # advance to the start of line 60
      initial_cpu_cycles = computer.cpu.cycles

      63.times { computer.cycle! } # one full line 60 (not a bad line)

      stolen = 63 - (computer.cpu.cycles - initial_cpu_cycles)
      expect(stolen).to be > 0
    end
  end

  describe "#load_prg" do
    subject(:load_addr) { computer.load_prg(prg_data) }

    let(:prg_data) { [0x01, 0x08, 0x1d, 0x08, 0x0a, 0x00, 0x99, 0x20] }

    specify { expect(load_addr).to eq(0x0801) }
    specify { expect(computer.ram.read(load_addr, 6)).to eq(prg_data[2..]) }
  end

  describe "interrupt delivery" do
    # Run from RAM with our own vectors and handlers.
    before { computer.address_bus.disable_overlays! }

    def load(addr, bytes)
      computer.ram.write(addr, bytes)
    end

    def arm_timer(cia)
      cia.interrupt_control.timer_a = true
      cia.control_a.start = true
      cia.timer_a_latch = 0x05
      cia.timer_a = 0x05
    end

    context "with a CIA1 timer IRQ" do
      before do
        load(0x1000, [0x4c, 0x00, 0x10]) # JMP $1000 (idle loop)
        # handler: LDA #$2A; STA $3000; JMP $2005
        load(0x2000, [0xa9, 0x2a, 0x8d, 0x00, 0x30, 0x4c, 0x05, 0x20])
        load(0xfffe, [0x00, 0x20]) # IRQ vector -> $2000
        computer.cpu.program_counter = 0x1000
        computer.cpu.status.interrupt = false
        arm_timer(computer.cia1)
      end

      it "runs the IRQ handler" do
        200.times { computer.cycle! }
        expect(computer.ram.peek(0x3000)).to eq(0x2a)
      end
    end

    context "with a CIA2 NMI" do
      before do
        load(0x1000, [0x4c, 0x00, 0x10]) # JMP $1000 (idle loop)
        load(0x2000, [0xee, 0x00, 0x30, 0x40]) # INC $3000; RTI
        load(0xfffa, [0x00, 0x20]) # NMI vector -> $2000
        computer.cpu.program_counter = 0x1000
        arm_timer(computer.cia2)
      end

      it "runs the NMI handler only once per edge" do
        200.times { computer.cycle! }
        expect(computer.ram.peek(0x3000)).to eq(1)
      end
    end

    context "with an acknowledged VIC raster IRQ" do
      before do
        computer.address_bus.poke(0x01, 0x05) # I/O mapped, ROMs as RAM
        load(0x1000, [0x4c, 0x00, 0x10]) # JMP $1000 (idle loop)
        # handler: LDA #$01; STA $D019 (ack); INC $3000; CLI; RTI
        load(0x2000, [0xa9, 0x01, 0x8d, 0x19, 0xd0, 0xee, 0x00, 0x30, 0x58, 0x40])
        load(0xfffe, [0x00, 0x20]) # IRQ vector -> $2000
        computer.cpu.program_counter = 0x1000
        computer.cpu.status.interrupt = false
        computer.vic.poke(0xd01a, 0x01) # enable raster IRQ
        computer.vic.poke(0xd012, 0x20) # raster compare = line 32
      end

      it "takes the IRQ only once after the handler acknowledges it" do
        (40 * 63).times { computer.cycle! } # past the compare line, one frame

        expect(computer.ram.peek(0x3000)).to eq(1)
      end
    end
  end

  describe "#mount" do
    let(:ram) { computer.ram }
    let(:writable) { instance_double(Badline::Storage::HostDirectory, write_file: nil) }
    let(:read_only) { instance_double(Badline::Storage::T64) }

    # Filename "DATA" at $0340, device 8, return address $1234 on the stack
    def request
      ram.write(0x0340, "DATA".bytes)
      ram.write(0xbb, [0x40, 0x03])
      ram.poke(0xb7, 4)
      ram.poke(0xba, 8)
      ram.poke(0xb9, 1)
      ram.write(0x01fe, [0x34, 0x12])
      computer.cpu.stack_pointer = 0xfd
    end

    def run_save
      request
      ram.write(0xc000, [0xaa, 0xbb])
      ram.write(0xc1, [0x00, 0xc0]) # start $c000
      ram.write(0xae, [0x02, 0xc0]) # end $c002
      run_routine(Badline::KernalTrap::Save::ADDRESS)
    end

    def run_load
      request
      run_routine(Badline::KernalTrap::Load::ADDRESS)
    end

    def run_routine(address)
      computer.cpu.program_counter = address
      computer.cpu.cycle!
    end

    context "with a backend that can write" do
      before do
        computer.mount(writable)
        run_save
      end

      it "saves through the backend" do
        expect(writable).to have_received(:write_file).with("DATA", [0x00, 0xc0, 0xaa, 0xbb])
      end
    end

    context "with a read-only backend" do
      before { computer.mount(read_only) }

      it "leaves SAVE to the ROM" do
        run_save
        expect(computer.cpu.stack_pointer).to eq(0xfd)
      end

      it "still serves LOAD" do
        allow(read_only).to receive(:read_file).with("DATA").and_return([0x00, 0xc0, 0x42])
        run_load
        expect(ram.peek(0xc000)).to eq(0x42)
      end
    end
  end
end
