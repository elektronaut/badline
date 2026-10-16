# frozen_string_literal: true

require "spec_helper"

describe Badline::KernalTrap::IEEELayout do
  # The first bytes of each IEEE primitive in each PET KERNAL, and the
  # code that names a zero-page variable: the ORA of FA that addresses a
  # device, and the ORA into ST that sets status bits.
  {
    "BASIC 1" => [
      Badline::KernalTrap::PET_BASIC1_LAYOUT, "pet/kernal1.rom",
      { talk: [0xa9, 0x40, 0xd0, 0x02], listen: [0xa9, 0x20, 0x48], second: [0x8d, 0x22, 0x02, 0x20, 0xf1, 0xf0],
        tksa: [0x8d, 0x22, 0x02, 0x20, 0xf1, 0xf0, 0x20, 0x4b, 0xf1], ciout: [0x2c, 0x1d, 0x02, 0x30, 0x05],
        untalk: [0xa9, 0x5f, 0xd0, 0x02], unlisten: [0xa9, 0x3f, 0x85, 0xf1], acptr: [0xa9, 0x34, 0x8d, 0x21, 0xe8] },
      { device: [0xf0e2, [0x05]], status: [0xfbe5, [0x0d]] }
    ],
    "BASIC 2" => [
      Badline::KernalTrap::PET_BASIC2_LAYOUT, "pet/kernal2.rom",
      { talk: [0xa9, 0x40, 0xd0, 0x02], listen: [0xa9, 0x20, 0x48], second: [0x85, 0xa5, 0x20, 0xee, 0xf0],
        tksa: [0x85, 0xa5, 0x20, 0xee, 0xf0, 0x20, 0x46, 0xf1], ciout: [0x24, 0xa0, 0x30, 0x04],
        untalk: [0xa9, 0x5f, 0xd0, 0x02], unlisten: [0xa9, 0x3f, 0xea, 0xea], acptr: [0xa9, 0x34, 0x8d, 0x21, 0xe8] },
      { device: [0xf0e0, [0x05]], status: [0xfb7f, [0x05]] }
    ],
    "BASIC 4" => [
      Badline::KernalTrap::PET_BASIC4_LAYOUT, "pet/kernal4.rom",
      { talk: [0xa9, 0x40, 0x2c], listen: [0xa9, 0x20, 0x48], second: [0x85, 0xa5, 0x20, 0x09, 0xf1],
        tksa: [0x85, 0xa5, 0x20, 0x09, 0xf1, 0x20, 0x75, 0xf1], ciout: [0x24, 0xa0, 0x30, 0x04],
        untalk: [0xad, 0x40, 0xe8, 0x29, 0xfb], unlisten: [0xa9, 0x3f, 0x20, 0xd7, 0xf0],
        acptr: [0xa9, 0x34, 0x8d, 0x21, 0xe8] },
      { device: [0xf0fb, [0x05]], status: [0xfbc4, [0x05]] }
    ]
  }.each do |name, (layout, rom, entries, variables)|
    context "with the PET #{name} KERNAL's" do
      let(:kernal) { Badline::ROM.read(rom) }

      def code(address, length) = kernal[address - 0xf000, length]

      entries.each do |entry, bytes|
        it "finds #{entry}" do
          expect(code(layout.public_send(entry), bytes.length)).to eq(bytes)
        end
      end

      variables.each do |variable, (address, opcode)|
        it "finds #{variable} where the ROM reads it" do
          operand = layout.zero_page.public_send(variable)
          bytes = operand > 0xff ? [operand & 0xff, operand >> 8] : [operand]
          expect(code(address, bytes.length + 1)).to eq(opcode + bytes)
        end
      end

      it "always finds the KERNAL" do
        expect(layout.kernal_mapped?(nil)).to be(true)
      end
    end
  end
end
