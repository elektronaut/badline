# frozen_string_literal: true

require "spec_helper"
require "badline/vic20"

describe Badline::KernalTrap::Layout do
  context "with the C64's" do
    let(:layout) { Badline::KernalTrap::C64_LAYOUT }
    let(:computer) { Badline::Computer.new }
    let(:bus) { computer.address_bus }

    describe "#kernal_mapped?" do
      it "finds the KERNAL in the power-on banking" do
        expect(layout.kernal_mapped?(bus)).to be(true)
      end

      it "finds RAM once the 6510 port banks the KERNAL out" do
        bus.poke(0x00, 0x2f)
        bus.poke(0x01, 0x35)
        expect(layout.kernal_mapped?(bus)).to be(false)
      end
    end

    describe "#release_serial_lines" do
      before do
        bus.poke(0xdd02, 0x3f)
        bus.poke(0xdd00, 0x3b)
      end

      it "lets go of ATN, the clock and the data line" do
        layout.release_serial_lines(bus)
        expect(bus.peek(0xdd00) & 0x38).to eq(0)
      end

      it "returns the port's outputs as it leaves them, the VIC bank bits kept" do
        expect(layout.release_serial_lines(bus) & 0x3f).to eq(0x03)
      end
    end

    describe "#time_serial_byte" do
      before { layout.time_serial_byte(bus, 0x04) }

      it "starts CIA 1's timer B one-shot from the high byte" do
        expect([computer.cia1.peek(0xdc07), computer.cia1.peek(0xdc0f) & 0x09]).to eq([0x04, 0x09])
      end
    end

    describe "#store_file" do
      before { layout.store_file(bus, 0xd020, [0x12]) }

      it "writes the RAM under the I/O" do
        expect(bus.ram.peek(0xd020)).to eq(0x12)
      end
    end
  end

  context "with the VIC-20's" do
    let(:layout) { Badline::KernalTrap::VIC20_LAYOUT }
    let(:machine) { Badline::Vic20.new }
    let(:bus) { machine.bus }

    # The first bytes of the ROM code each entry point should hold, in
    # both KERNALs. The vector targets are where the default vectors at
    # $FD6D point ILOAD ($0330) and ISAVE ($0332).
    {
      load: [0x85, 0x93], save: [0xa5, 0xba],
      searching_message: [0xa5, 0x9d, 0x10, 0x1e, 0xa0, 0x0c], loading_message: [0xa0, 0x49, 0xa5, 0x93],
      load_byte_loop: [0xa9, 0xfd, 0x25, 0x90], load_done: [0x18, 0xa6, 0xae, 0xa4, 0xaf, 0x60],
      file_not_found_exit: [0xa9, 0x04], missing_file_name_exit: [0xa9, 0x08],
      saving_message: [0xa5, 0x9d, 0x10, 0xfb, 0xa0, 0x51], clock_release: [0xad, 0x2c, 0x91, 0x29, 0xfd],
      data_release: [0xad, 0x2c, 0x91, 0x29, 0xdf], save_done: [0x18, 0x60]
    }.each do |entry, code|
      %w[kernal-pal kernal-ntsc].each do |rom|
        it "finds #{entry} in #{rom}" do
          kernal = Badline::ROM.read("vic20/#{rom}.rom")
          expect(kernal[layout.public_send(entry) - 0xe000, code.length]).to eq(code)
        end
      end
    end

    it "points the default ILOAD and ISAVE vectors at LOAD and SAVE" do
      kernal = Badline::ROM.read("vic20/kernal-pal.rom")
      vectors = [layout.load, layout.save].flat_map { |address| [address & 0xff, address >> 8] }
      expect(kernal[0xfd89 - 0xe000, 4]).to eq(vectors)
    end

    {
      talk: 0xffb4, listen: 0xffb1, second: 0xff93, tksa: 0xff96,
      ciout: 0xffa8, untalk: 0xffab, unlisten: 0xffae, acptr: 0xffa5
    }.each do |entry, vector|
      it "finds #{entry} where the jump table at $#{vector.to_s(16)} jumps" do
        target = layout.public_send(entry)
        kernal = Badline::ROM.read("vic20/kernal-pal.rom")
        expect(kernal[vector - 0xe000, 3]).to eq([0x4c, target & 0xff, target >> 8])
      end
    end

    describe "#kernal_mapped?" do
      it "always finds the KERNAL" do
        expect(layout.kernal_mapped?(bus)).to be(true)
      end
    end

    describe "#release_serial_lines" do
      before do
        bus.poke(0x9113, 0x80)
        bus.poke(0x911f, 0x80)
        bus.poke(0x912c, 0xee)
      end

      it "lets go of ATN on VIA 1's PA7" do
        layout.release_serial_lines(bus)
        expect(machine.via1.port_a_output & 0x80).to eq(0)
      end

      it "drives VIA 2's CA2 and CB2 low, letting go of the clock and the data line" do
        layout.release_serial_lines(bus)
        expect(machine.via2.pcr).to eq(0xcc)
      end

      it "returns the PCR as it leaves it" do
        expect(layout.release_serial_lines(bus)).to eq(0xcc)
      end
    end

    describe "#time_serial_byte" do
      before { layout.time_serial_byte(bus, 0x04) }

      it "starts VIA 2's timer 2 from the high byte" do
        expect(machine.via2.timer2 >> 8).to eq(0x04)
      end
    end

    describe "#store_file" do
      it "writes through the bus, to colour RAM" do
        layout.store_file(bus, 0x9400, [0x05])
        expect(bus.color_ram.nibble(0x9400)).to eq(0x05)
      end

      it "writes nothing into an empty block" do
        layout.store_file(bus, 0x2000, [0x12])
        expect(bus.ram.peek(0x2000)).to eq(0xff)
      end
    end
  end

  context "with the C128's" do
    let(:layout) { Badline::KernalTrap::C128_LAYOUT }
    let(:machine) { Badline::C128.new(mode: :c128) }
    let(:bus) { machine.address_bus }
    let(:kernal) { Badline::ROM.read("c128/kernal.rom") }

    def rom(address, length) = kernal[address - 0xc000, length]

    {
      talk: 0xffb4, listen: 0xffb1, second: 0xff93, tksa: 0xff96,
      ciout: 0xffa8, untalk: 0xffab, unlisten: 0xffae, acptr: 0xffa5
    }.each do |entry, vector|
      it "finds #{entry} where the jump table at $#{vector.to_s(16)} jumps" do
        target = layout.public_send(entry)
        expect(rom(vector, 3)).to eq([0x4c, target & 0xff, target >> 8])
      end
    end

    it "points the default ILOAD and ISAVE vectors at LOAD and SAVE" do
      vectors = [layout.load, layout.save].flat_map { |address| [address & 0xff, address >> 8] }
      expect(rom(0xe08f, 4)).to eq(vectors)
    end

    {
      load_done: [0x18, 0xa6, 0xae, 0xa4, 0xaf, 0x60], save_done: [0x18, 0x60],
      loading_message: [0xa0, 0x49, 0xa5, 0x93], searching_message: [0xa5, 0x9d, 0x10],
      saving_message: [0xa5, 0x9d, 0x10, 0x37, 0xa0, 0x51], file_not_found_exit: [0xa9, 0x04],
      missing_file_name_exit: [0xa9, 0x08], load_byte_loop: [0xa9, 0xfd, 0x25, 0x90],
      clock_release: [0xad, 0x00, 0xdd, 0x29, 0xef], data_release: [0xad, 0x00, 0xdd, 0x29, 0xdf]
    }.each do |entry, code|
      it "finds #{entry} in the ROM" do
        expect(rom(layout.public_send(entry), code.length)).to eq(code)
      end
    end

    describe "#kernal_mapped?" do
      it "finds the KERNAL in the reset configuration" do
        expect(layout.kernal_mapped?(bus)).to be(true)
      end

      it "finds RAM once CR maps it at $C000" do
        bus.poke(0xff00, 0x3e)
        expect(layout.kernal_mapped?(bus)).to be(false)
      end

      it "finds no C128 KERNAL in C64 mode" do
        bus.poke(0xd505, 0xf7)
        expect(layout.kernal_mapped?(bus)).to be(false)
      end
    end

    describe "#time_serial_byte" do
      it "leaves CIA 1's timer B alone, as the ROM's loops time the bytes" do
        expect { layout.time_serial_byte(bus, 0x04) }.not_to(change { machine.cia1.peek(0xdc07) })
      end
    end

    describe "#store_file" do
      it "writes into the RAM bank BA names" do
        bus.poke(0xc6, 1)
        layout.store_file(bus, 0x2000, [0x12])
        expect([bus.ram.peek(0x12000), bus.ram.peek(0x2000)]).to eq([0x12, Badline::C128::Bus::RAM_POWER_ON[0x2000]])
      end
    end

    describe "#filename_byte" do
      it "reads the file name from the RAM bank FNBANK names" do
        bus.poke(0xc7, 1)
        bus.ram.poke(0x13000, 0x41)
        expect(layout.filename_byte(bus, 0x3000)).to eq(0x41)
      end
    end
  end
end
