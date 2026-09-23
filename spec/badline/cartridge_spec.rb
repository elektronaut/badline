# frozen_string_literal: true

require "spec_helper"

describe Badline::Cartridge do
  let(:address_bus) { Badline::AddressBus.new }

  def chip(bank:, address:, data:)
    Badline::Storage::CRTFile::Chip.new(chip_type: 0, bank:, address:, data:)
  end

  def crt(hardware_type:, exrom:, game:, chips:)
    instance_double(Badline::Storage::CRTFile, hardware_type:, exrom:, game:, name: "TEST", chips:)
  end

  describe ".from_crt" do
    it "raises on unsupported hardware types" do
      expect { described_class.from_crt(crt(hardware_type: 3, exrom: 0, game: 1, chips: [])) }
        .to raise_error(described_class::UnsupportedTypeError)
    end
  end

  describe "an 8K cartridge" do
    let(:chips) { [chip(bank: 0, address: 0x8000, data: [0x42] * 0x2000)] }
    let(:cartridge) do
      described_class.from_crt(crt(hardware_type: 0, exrom: 0, game: 1, chips:))
    end

    before { address_bus.attach_cartridge(cartridge) }

    it "maps ROML at $8000" do
      expect(address_bus[0x8000]).to eq(0x42)
    end

    it "keeps BASIC mapped at $A000" do
      expect(address_bus[0xa000]).to eq(0x94)
    end

    it "writes through to the RAM below" do
      address_bus[0x8000] = 0x55
      expect(address_bus.ram[0x8000]).to eq(0x55)
    end

    it "unmaps ROML when LORAM is cleared" do
      address_bus[0x00] = 0x2f
      address_bus[0x01] = 0b00110110
      expect(address_bus[0x8000]).to eq(0x00)
    end
  end

  describe "a 16K cartridge" do
    let(:chips) do
      [chip(bank: 0, address: 0x8000, data: [0x42] * 0x2000),
       chip(bank: 0, address: 0xa000, data: [0x43] * 0x2000)]
    end
    let(:cartridge) do
      described_class.from_crt(crt(hardware_type: 0, exrom: 0, game: 0, chips:))
    end

    before { address_bus.attach_cartridge(cartridge) }

    it "maps ROML at $8000" do
      expect(address_bus[0x8000]).to eq(0x42)
    end

    it "maps ROMH over BASIC at $A000" do
      expect(address_bus[0xa000]).to eq(0x43)
    end

    it "keeps the KERNAL mapped" do
      expect(address_bus[0xe000]).to eq(address_bus.kernal_rom[0xe000])
    end

    context "with LORAM set and HIRAM cleared" do
      before do
        address_bus.ram.poke(0xd000, 0x5a)
        address_bus[0x00] = 0x2f
      end

      it "maps RAM over the character ROM" do
        address_bus[0x01] = 0b00110001
        expect(address_bus[0xd000]).to eq(0x5a)
      end

      it "still maps I/O" do
        address_bus[0x01] = 0b00110101
        expect(address_bus[0xd000]).to eq(address_bus.vic.peek(0xd000))
      end
    end
  end

  describe "a 16K cartridge with a single chip" do
    let(:chips) do
      [chip(bank: 0, address: 0x8000,
            data: ([0x42] * 0x2000) + ([0x43] * 0x2000))]
    end
    let(:cartridge) do
      described_class.from_crt(crt(hardware_type: 0, exrom: 0, game: 0, chips:))
    end

    before { address_bus.attach_cartridge(cartridge) }

    it "splits the chip across ROML and ROMH" do
      expect(address_bus[0xa000]).to eq(0x43)
    end
  end

  describe "an Ultimax cartridge" do
    let(:romh_data) do
      ([0x4c] * 0x2000).tap do |data|
        data[0x1ffc] = 0x34
        data[0x1ffd] = 0x12
      end
    end
    let(:chips) { [chip(bank: 0, address: 0xe000, data: romh_data)] }
    let(:cartridge) do
      described_class.from_crt(crt(hardware_type: 0, exrom: 1, game: 0, chips:))
    end

    before { address_bus.attach_cartridge(cartridge) }

    it "maps ROMH at $E000" do
      expect(address_bus[0xe000]).to eq(0x4c)
    end

    it "ignores the $01 banking lines" do
      address_bus.disable_overlays!
      expect(address_bus[0xe000]).to eq(0x4c)
    end

    it "reads open bus from the unmapped address space" do
      expect(address_bus[0x2000]).to eq(address_bus.vic.phi1_data)
    end

    it "drops writes to the open address space" do
      address_bus[0x2001] = 0x55
      expect(address_bus.ram[0x2001]).to eq(0x00)
    end

    it "keeps the low 4K of RAM" do
      address_bus[0x0400] = 0x12
      expect(address_bus[0x0400]).to eq(0x12)
    end

    it "exposes ROMH to the VIC at $3000-$3FFF" do
      bank = Badline::VIC::Bank.new(address_bus)
      expect(bank.peek(0x3000)).to eq(0x4c)
    end

    it "reads VIC fetches below $3000 from RAM" do
      bank = Badline::VIC::Bank.new(address_bus)
      expect(bank.peek(0x1000)).to eq(0x00)
    end

    it "resets the CPU through the cartridge vector" do
      computer = Badline::Computer.new
      computer.attach_cartridge(cartridge)
      expect(computer.cpu.program_counter).to eq(0x1234)
    end
  end

  describe "a 4K Ultimax cartridge" do
    let(:chips) { [chip(bank: 0, address: 0xf000, data: [0x4d] * 0x1000)] }
    let(:cartridge) do
      described_class.from_crt(crt(hardware_type: 0, exrom: 1, game: 0, chips:))
    end

    before { address_bus.attach_cartridge(cartridge) }

    it "mirrors the chip across the full ROMH window" do
      expect(address_bus[0xe000]).to eq(0x4d)
    end
  end

  describe "a Magic Desk cartridge" do
    let(:chips) do
      [chip(bank: 0, address: 0x8000, data: [0x10] * 0x2000),
       chip(bank: 1, address: 0x8000, data: [0x11] * 0x2000)]
    end
    let(:cartridge) do
      described_class.from_crt(crt(hardware_type: 19, exrom: 0, game: 1, chips:))
    end

    before { address_bus.attach_cartridge(cartridge) }

    it "boots with bank 0" do
      expect(address_bus[0x8000]).to eq(0x10)
    end

    it "switches banks on $DE00 writes" do
      address_bus[0xde00] = 1
      expect(address_bus[0x8000]).to eq(0x11)
    end

    it "disables the ROM when bit 7 is set" do
      address_bus[0xde00] = 0x80
      expect(address_bus[0x8000]).to eq(0x00)
    end

    it "re-enables the ROM when bit 7 is cleared" do
      address_bus[0xde00] = 0x80
      address_bus[0xde00] = 0x00
      expect(address_bus[0x8000]).to eq(0x10)
    end
  end

  describe "an Ocean cartridge" do
    let(:chips) do
      [chip(bank: 0, address: 0x8000, data: [0x20] * 0x2000),
       chip(bank: 1, address: 0x8000, data: [0x21] * 0x2000)]
    end
    let(:cartridge) do
      described_class.from_crt(crt(hardware_type: 5, exrom: 0, game: 0, chips:))
    end

    before { address_bus.attach_cartridge(cartridge) }

    it "boots with bank 0" do
      expect(address_bus[0x8000]).to eq(0x20)
    end

    it "switches banks on $DE00 writes" do
      address_bus[0xde00] = 0x81
      expect(address_bus[0x8000]).to eq(0x21)
    end

    it "mirrors the selected bank at $A000" do
      address_bus[0xde00] = 0x81
      expect(address_bus[0xa000]).to eq(0x21)
    end
  end
end
