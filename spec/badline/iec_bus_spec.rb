# frozen_string_literal: true

require "spec_helper"
require_relative "../support/drive1541_rom"

describe Badline::IECBus do
  context "with the C64 and a drive on it" do
    let(:computer) { Badline::Computer.new }
    let(:drive) { Badline::Drive1541.new(rom: Drive1541ROM.stub) }
    let(:bus) { computer.iec_bus }

    # CIA 2 port A: PA3 ATN OUT, PA4 CLK OUT, PA5 DATA OUT, PA6 CLK IN,
    # PA7 DATA IN. PA0-2 are outputs the serial bus leaves alone.
    def c64_drive(bits) = computer.cia2.poke(0xdd00, bits)

    def c64_lines = computer.cia2.peek(0xdd00)

    def run(cycles) = cycles.times { computer.cycle! }

    # Asserts ATN, then releases it, for 50 cycles each.
    def pulse_atn
      c64_drive(0x0f)
      run(50)
      c64_drive(0x07)
      run(50)
    end

    # Puts a program at $0300, where the stub ROM's reset vector points.
    def load(bytes, at: 0x0300) = drive.ram.write(at, bytes)

    # Stops the C64's CPU so only the chips and the drive run.
    def halt_c64
      computer.ram.write(0x0200, [0x4c, 0x00, 0x02]) # JMP *
      computer.address_bus.poke(0x01, 0x30) # all RAM
      computer.cpu.program_counter = 0x0200
    end

    before do
      halt_c64
      computer.cia2.poke(0xdd02, 0x3f)
      c64_drive(0x07) # the VIC bank bits, every serial line released
      computer.attach_drive1541(drive)
    end

    describe "from the C64 to the drive" do
      before do
        # LDA #$1A; STA DDRB; LDA #$00; STA ORB; loop: LDA ORB; STA $10; JMP loop
        load([0xa9, 0x1a, 0x8d, 0x02, 0x18, 0xa9, 0x00, 0x8d, 0x00, 0x18,
              0xad, 0x00, 0x18, 0x85, 0x10, 0x4c, 0x0a, 0x03])
      end

      it "reads every line released" do
        run(50)
        expect(drive.ram.peek(0x10) & 0x85).to eq(0x00)
      end

      it "reads ATN IN on PB7, with DATA IN from its own acknowledge gate" do
        c64_drive(0x0f)
        run(50)
        expect(drive.ram.peek(0x10) & 0x85).to eq(0x81)
      end

      it "reads CLK IN on PB2" do
        c64_drive(0x17)
        run(50)
        expect(drive.ram.peek(0x10) & 0x85).to eq(0x04)
      end

      it "reads DATA IN on PB0" do
        c64_drive(0x27)
        run(50)
        expect(drive.ram.peek(0x10) & 0x85).to eq(0x01)
      end
    end

    describe "from the drive to the C64" do
      # LDA #$1A; STA DDRB; LDA #value; STA ORB; JMP *
      def drive_port_b(value)
        load([0xa9, 0x1a, 0x8d, 0x02, 0x18, 0xa9, value, 0x8d, 0x00, 0x18, 0x4c, 0x0a, 0x03])
        run(50)
      end

      it "reads every line released" do
        drive_port_b(0x00)
        expect(c64_lines & 0xc0).to eq(0xc0)
      end

      it "reads CLK IN low on PA6" do
        drive_port_b(0x08)
        expect(c64_lines & 0xc0).to eq(0x80)
      end

      it "reads DATA IN low on PA7" do
        drive_port_b(0x02)
        expect(c64_lines & 0xc0).to eq(0x40)
      end

      it "leaves the VIC bank bits alone" do
        drive_port_b(0x0a)
        expect(c64_lines & 0x07).to eq(0x07)
      end
    end

    describe "wired-AND" do
      before do
        drive.via1.poke(0x1802, 0x1a)
        drive.via1.poke(0x1800, 0x0a) # CLK and DATA pulled
        c64_drive(0x37) # CLK and DATA pulled
      end

      it "holds a line low while both sides pull it" do
        expect([bus.clk_low?, bus.data_low?]).to eq([true, true])
      end

      it "holds it low while the drive alone pulls it" do
        c64_drive(0x07)
        expect([bus.clk_low?, bus.data_low?]).to eq([true, true])
      end

      it "holds it low while the C64 alone pulls it" do
        drive.via1.poke(0x1800, 0x00)
        expect([bus.clk_low?, bus.data_low?]).to eq([true, true])
      end

      it "lets it go high once both release it" do
        drive.via1.poke(0x1800, 0x00)
        c64_drive(0x07)
        expect([bus.clk_low?, bus.data_low?]).to eq([false, false])
      end
    end

    describe "the ATN acknowledge gate" do
      before { drive.via1.poke(0x1802, 0x1a) }

      it "pulls DATA as ATN goes low while ATNA is clear" do
        c64_drive(0x0f)
        expect(c64_lines & 0x80).to eq(0)
      end

      it "releases DATA once the drive sets ATNA" do
        c64_drive(0x0f)
        drive.via1.poke(0x1800, 0x10)
        expect(c64_lines & 0x80).to eq(0x80)
      end

      it "pulls DATA while ATNA is set and ATN is released" do
        drive.via1.poke(0x1800, 0x10)
        expect(c64_lines & 0x80).to eq(0)
      end

      it "shows the drive DATA IN low too" do
        c64_drive(0x0f)
        drive.host_cycle!
        expect(drive.via1.peek(0x1800) & 0x01).to eq(0x01)
      end

      # Pinned by the same rows as ATN on CA1 below.
      it "shows the drive the C64's CLK from the host cycle after the write" do
        c64_drive(0x17)
        flags = [drive.via1.peek(0x1800) & 0x04]
        drive.host_cycle!
        expect(flags << (drive.via1.peek(0x1800) & 0x04)).to eq([0x00, 0x04])
      end
    end

    describe "ATN on VIA 1's CA1" do
      before do
        # LDA #$01; STA PCR (CA1 rising edge); LDA #$82; STA IER; CLI; JMP *
        load([0xa9, 0x01, 0x8d, 0x0c, 0x18, 0xa9, 0x82, 0x8d, 0x0e, 0x18, 0x58, 0x4c, 0x0b, 0x03])
        load([0xe6, 0x10, 0xad, 0x01, 0x18, 0x40], at: 0x0400) # INC $10; LDA ORA (clears CA1); RTI
        run(50)
      end

      it "takes no interrupt while ATN stays released" do
        run(50)
        expect(drive.ram.peek(0x10)).to eq(0)
      end

      it "interrupts the drive as the C64 asserts ATN" do
        c64_drive(0x0f)
        run(50)
        expect(drive.ram.peek(0x10)).to eq(1)
      end

      it "takes no interrupt as ATN is released" do
        pulse_atn
        expect(drive.ram.peek(0x10)).to eq(1)
      end

      it "interrupts again on the next assertion" do
        pulse_atn
        pulse_atn
        expect(drive.ram.peek(0x10)).to eq(2)
      end

      # The C64's CIA changes the line at the end of its cycle, after the
      # drive has sampled it for the cycles that run alongside. Pinned by
      # VICE-testprogs drive/selftest, drive/scanner and drive/viavarious
      # (see doc/pinned-behaviour.md, 1541 serial port).
      it "sees an assertion from the host cycle after the one it lands in" do
        c64_drive(0x0f)
        drive.host_cycle!
        flags = [drive.via1.interrupt_flags & 0x02]
        drive.host_cycle!
        expect(flags << (drive.via1.interrupt_flags & 0x02)).to eq([0x00, 0x02])
      end
    end

    describe "the device number jumpers" do
      it "read 00 on PB5 and PB6 for device 8" do
        expect(drive.via1.peek(0x1800) & 0x60).to eq(0x00)
      end

      it "read 11 for device 11" do
        drive = Badline::Drive1541.new(rom: Drive1541ROM.stub, device: 11)
        computer.attach_drive1541(drive)
        expect(drive.via1.peek(0x1800) & 0x60).to eq(0x60)
      end
    end

    describe "a drive swapped for another" do
      let(:second) { Badline::Drive1541.new(rom: Drive1541ROM.stub) }

      before do
        drive.via1.poke(0x1802, 0x1a)
        drive.via1.poke(0x1800, 0x0a) # CLK and DATA pulled
        second.via1.poke(0x1802, 0x1a)
        second.via1.poke(0x1800, 0x10) # released, ATNA set
        c64_drive(0x0f)
        computer.attach_drive1541(second)
      end

      it "leaves the bus with the first drive" do
        expect(bus.drives).to eq([second])
      end

      it "no longer sees the first drive's lines" do
        expect(c64_lines & 0xc0).to eq(0xc0)
      end
    end

    describe "a drive on a bus of its own" do
      subject(:alone) { Badline::Drive1541.new(rom: Drive1541ROM.stub) }

      it "reads its own lines back" do
        alone.via1.poke(0x1802, 0x1a)
        alone.via1.poke(0x1800, 0x08) # CLK OUT
        expect(alone.via1.peek(0x1800) & 0x85).to eq(0x04)
      end
    end
  end

  # Needs the real DOS ROM, which the repository doesn't ship. The C64
  # boots with the drive on the bus, and BASIC reads the power-on message
  # from the drive's error channel over the real serial bus, since the
  # serial traps don't answer device 8 with a true drive attached. INPUT#
  # is illegal in direct mode, so it runs as a program line.
  describe "with the DOS ROM" do
    let(:computer) { Badline::Computer.new }
    let(:rom_file) { File.join(Badline.rom_path, "dos1541.rom") }

    before do
      skip "needs #{rom_file}: the 1541 DOS, 325302-01 and 901229-05 as one 16 KB image" unless File.exist?(rom_file)
      computer.attach_drive1541(Badline::Drive1541.new)
    end

    it "reads the power-on message from the drive's error channel" do
      output = computer.capture_output
      computer.on_init { computer.type_text("1open15,8,15:input#15,a,b$,c,d:printa;b$;c;d\rrun\r") }
      7_000_000.times { computer.cycle! }
      # PRINT follows each number with a cursor right, which CHROUT capture drops
      expect(output.output.upcase).to include(" 73CBM DOS V2.6 1541 0 0")
    end
  end
end
