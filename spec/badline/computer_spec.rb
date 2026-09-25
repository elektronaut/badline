# frozen_string_literal: true

require "spec_helper"
require_relative "../support/cartridge_builder"

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

  describe "the CIA model" do
    it "fits 6526s unless given" do
      expect([computer.cia1.model, computer.cia2.model]).to eq(%i[mos6526 mos6526])
    end

    it "fits the model given to both CIAs" do
      computer = described_class.new(cia_model: :mos6526a)
      expect([computer.cia1.model, computer.cia2.model]).to eq(%i[mos6526a mos6526a])
    end
  end

  describe "light pen on control port 1" do
    before { 100.times { computer.cycle! } }

    it "leaves the latch clear while the fire button is up" do
      expect(computer.vic.peek(0xd019) & 0x08).to eq(0x00)
    end

    it "latches when joystick 1 fires" do
      computer.joystick1.press(:fire)
      computer.cycle!
      expect(computer.vic.peek(0xd019) & 0x08).to eq(0x08)
    end

    it "latches the current raster line" do
      computer.joystick1.press(:fire)
      computer.cycle!
      expect(computer.vic.peek(0xd014)).to eq(1)
    end
  end

  describe "the VIC's open bus" do
    it "reads RAM at the CPU's program counter" do
      computer.ram.poke(0x3000, 0x8a)
      computer.cpu.program_counter = 0x3000
      expect(computer.vic.instance_variable_get(:@open_bus).call).to eq(0x8a)
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

  describe "#attach_cartridge on a running machine" do
    let(:cartridge) do
      chips = [Badline::Storage::CRTFile::Chip.new(chip_type: 0, bank: 0, address: 0x8000, data: [0] * 0x2000)]
      Badline::Cartridge.from_crt(
        instance_double(Badline::Storage::CRTFile, hardware_type: 0, exrom: 0, game: 1, name: "TEST", chips:)
      )
    end

    # LDA #$ff; STA $dc02; STA $dd03; LDA #$2f; STA $00; LDA #$36; STA $01;
    # LDA #$19; STA $dc0e; LDA #$0f; STA $d418; STA $dc04; LDA #$08;
    # STA $d412; LDA #$81; STA $dd0d; JMP *
    let(:program) do
      [0xa9, 0xff, 0x8d, 0x02, 0xdc, 0x8d, 0x03, 0xdd, 0xa9, 0x2f, 0x85, 0x00,
       0xa9, 0x36, 0x85, 0x01, 0xa9, 0x19, 0x8d, 0x0e, 0xdc, 0xa9, 0x0f, 0x8d,
       0x18, 0xd4, 0x8d, 0x04, 0xdc, 0xa9, 0x08, 0x8d, 0x12, 0xd4, 0xa9, 0x81,
       0x8d, 0x0d, 0xdd, 0x4c, 0x27, 0xc0]
    end

    let(:fresh) { described_class.new }

    def vic_registers(machine)
      Array.new(0x2f) { |register| machine.address_bus.peek(0xd000 + register) }
    end

    before do
      computer.ram.write(0xc000, program)
      computer.cpu.program_counter = 0xc000
      computer.cpu.status.interrupt = true
      { 0xd011 => 0x3b, 0xd012 => 0x80, 0xd01a => 0x0f, 0xd020 => 0x05, 0xd021 => 0x06 }
        .each { |address, value| computer.address_bus.poke(address, value) }
      (63 * 200).times { computer.cycle! }
      computer.attach_cartridge(cartridge)
    end

    it "takes the VIC's registers back to their power-on values" do
      expect(vic_registers(computer)).to eq(vic_registers(fresh))
    end

    it "takes the VIC back to the top of the frame" do
      expect([computer.vic.rasterline, computer.vic.column]).to eq([0, 0])
    end

    it "drops the VIC's interrupt" do
      expect(computer.vic.interrupted?).to be(false)
    end

    it "clears RAM" do
      expect(computer.ram.read(0xc000, program.length)).to all(eq(0))
    end

    it "clears the CPU port's direction register" do
      expect(computer.address_bus.peek(0x00)).to eq(0x00)
    end

    it "reads the port's pulled-up lines" do
      expect(computer.address_bus.peek(0x01) & 0x07).to eq(0x07)
    end

    it "takes CIA 1's ports back to inputs" do
      expect(computer.cia1.peek(0xdc02)).to eq(0x00)
    end

    it "takes CIA 2's ports back to inputs" do
      expect(computer.cia2.peek(0xdd03)).to eq(0x00)
    end

    it "stops CIA 1's timer A" do
      expect(computer.cia1.control_a.value).to eq(0x00)
    end

    it "fills CIA 1's timer A latch" do
      expect(computer.cia1.timer_a_latch).to eq(0xffff)
    end

    it "masks CIA 2's interrupts" do
      expect(computer.cia2.interrupt_control.value).to eq(0x00)
    end

    it "clears the SID's registers" do
      expect(computer.sid.register(0x18)).to eq(0x00)
    end

    it "clears the SID's filter" do
      expect(computer.sid.filter.volume).to eq(0x00)
    end

    it "leaves the SID's accumulators alone" do
      expect(computer.sid.voices[2].waveform.accumulator).to eq(0x000000)
    end

    it "runs from the KERNAL's reset vector" do
      expect(computer.cpu.program_counter).to eq(0xfce2)
    end
  end

  # SID/writedelay pins the 6581 latching a register write a cycle late.
  # Nothing inside SID delays it: the DSP is clocked ahead of the CPU in
  # #cycle!, so a store lands after the cycle it was issued on. Clocking the
  # SID after the CPU instead makes the write take hold a cycle early, and
  # every SID unit spec still passes.
  describe "SID writes against the clock order" do
    # LDA #$01; STA $d400; NOP... — voice 1's frequency, written on the
    # store's fourth cycle. The accumulator then steps by 1 per clock.
    before do
      computer.ram.write(0xc000, [0xa9, 0x01, 0x8d, 0x00, 0xd4] + ([0xea] * 6))
      computer.cpu.program_counter = 0xc000
    end

    def accumulator = computer.sid.voices[0].waveform.accumulator

    context "with the DSP synthesizing" do
      before { computer.sid.synthesize! }

      it "has not clocked the frequency on the store's own cycle" do
        6.times { computer.cycle! }
        expect(accumulator).to eq(0x555555)
      end

      it "clocks it on the cycle after the store" do
        7.times { computer.cycle! }
        expect(accumulator).to eq(0x555556)
      end
    end

    context "with the DSP idle, replaying the write" do
      it "has not clocked the frequency on the store's own cycle" do
        6.times { computer.cycle! }
        computer.sid.osc3
        expect(accumulator).to eq(0x555555)
      end

      it "clocks it on the cycle after the store" do
        7.times { computer.cycle! }
        computer.sid.osc3
        expect(accumulator).to eq(0x555556)
      end
    end
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

    # Filename at $0340, device 8, return address $1234 on the stack
    def request(name = "DATA")
      ram.write(0x0340, name.bytes)
      ram.write(0xbb, [0x40, 0x03])
      ram.poke(0xb7, name.length)
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

    def run_load(name = "DATA")
      request(name)
      run_routine(Badline::KernalTrap::Load::ADDRESS)
    end

    def run_routine(address)
      computer.cpu.program_counter = address
      computer.cpu.cycle!
    end

    def return_to_caller
      500.times do
        break if computer.cpu.program_counter == 0x1235

        computer.cpu.step!
      end
    end

    context "with a backend that can write" do
      before do
        computer.mount(writable)
        run_save
        return_to_caller
      end

      it "saves through the backend" do
        expect(writable).to have_received(:write_file).with("DATA", [0x00, 0xc0, 0xaa, 0xbb])
      end
    end

    context "when the disk changes" do
      let(:second_disk) do
        instance_double(Badline::Storage::D64Image, first_block: nil, read_file_at: [0x00, 0xc0, 0x02])
      end

      before do
        computer.mount(instance_double(Badline::Storage::D64Image, read_file: [0x00, 0xc0, 0x01],
                                                                   first_block: [17, 0], read_error: nil))
        run_load
        return_to_caller
        computer.mount(second_disk)
        run_load("*")
      end

      it "keeps the drive's RAM, where the last LOAD left its first block" do
        expect(second_disk).to have_received(:read_file_at).with(17, 0)
      end
    end

    context "when the machine resets" do
      let(:disk) do
        instance_double(Badline::Storage::D64Image, read_file: [0x00, 0xc0, 0x01], first_block: [17, 0],
                                                    read_file_at: [0x00, 0xc0, 0x02], read_error: nil)
      end

      before do
        computer.mount(disk)
        run_load
        return_to_caller
        computer.reset!
        run_load("*")
      end

      it "resets the drive, whose RAM forgets the last LOAD's first block" do
        expect(disk).not_to have_received(:read_file_at)
      end
    end

    context "with a read-only backend" do
      before { computer.mount(read_only) }

      it "leaves SAVE to the ROM" do
        run_save
        expect(computer.cpu.stack_pointer).to eq(0xfd)
      end

      it "still serves LOAD" do
        allow(read_only).to receive(:read_file).with("DATA", type: :prg).and_return([0x00, 0xc0, 0x42])
        run_load
        expect(ram.peek(0xc000)).to eq(0x42)
      end
    end
  end

  describe "the cartridge freeze button" do
    include CartridgeBuilder

    # A bank whose NMI vector points at a JMP to itself at $E000.
    let(:rom) do
      Array.new(0x2000, 0xea).tap do |data|
        data[0, 3] = [0x4c, 0x00, 0xe0]
        data[0x1ffa, 2] = [0x00, 0xe0]
      end
    end
    let(:chips) { [Badline::Storage::CRTFile::Chip.new(chip_type: 0, bank: 0, address: 0x8000, data: rom)] }

    before do
      computer.attach_cartridge(build_cartridge(1, chips))
      10_000.times { computer.cycle! }
    end

    it "runs the cartridge's NMI handler" do
      computer.press_cartridge_button
      100.times { computer.cycle! }
      expect(computer.cpu.program_counter).to be_between(0xe000, 0xe002)
    end

    it "leaves the freeze on reset" do
      computer.press_cartridge_button
      100.times { computer.cycle! }
      computer.reset!
      expect(computer.address_bus.ultimax).to be(false)
    end

    it "waits for the interrupt to push before entering Ultimax mode" do
      computer.press_cartridge_button
      computer.cycle!
      expect(computer.address_bus.ultimax).to be(false)
    end

    context "with the cartridge holding NMI" do
      def fire_cia2_timer
        { 0xdd0d => 0x81, 0xdd04 => 0x01, 0xdd05 => 0x00, 0xdd0e => 0x19 }.each do |reg, value|
          computer.cia2.poke(reg, value)
        end
        100.times { computer.cycle! }
      end

      before do
        computer.press_cartridge_button
        100.times { computer.cycle! }
      end

      it "takes no NMI from CIA 2" do
        expect { fire_cia2_timer }.not_to(change { computer.cpu.stack_pointer })
      end
    end
  end

  it "ignores the freeze button without a cartridge" do
    expect { computer.press_cartridge_button }.not_to raise_error
  end
end
