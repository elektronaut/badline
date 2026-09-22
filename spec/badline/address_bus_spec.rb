# frozen_string_literal: true

require "spec_helper"

describe Badline::AddressBus do
  let(:address_bus) { described_class.new }

  specify { expect(address_bus[0x0000]).to eq(0x2f) }
  specify { expect(address_bus[0x0001]).to eq(0b00110111) }

  describe "the processor port" do
    context "when all bits are inputs" do
      before do
        address_bus[0x01] = 0x34
        address_bus[0x00] = 0x00
      end

      specify { expect(address_bus[0x01]).to eq(0x17) }

      it "keeps the ROMs banked in" do
        expect(address_bus[0xa000]).to eq(0x94)
      end
    end

    context "when the ROMs are banked out through output bits" do
      before do
        address_bus[0xa000] = 0x20
        address_bus[0x00] = 0xff
        address_bus[0x01] = 0x34
      end

      specify { expect(address_bus[0x01]).to eq(0x34) }

      it "unmaps the BASIC ROM" do
        expect(address_bus[0xa000]).to eq(0x20)
      end
    end

    context "when bit 5 becomes an input" do
      before { address_bus[0x00] = 0x0f }

      specify { expect(address_bus[0x01] & 0x20).to eq(0) }
    end

    context "when a floating bit was driven high before becoming an input" do
      before do
        address_bus[0x00] = 0xff
        address_bus[0x01] = 0xb7
        address_bus[0x00] = 0x2f
      end

      specify { expect(address_bus[0x01]).to eq(0xb7) }
    end

    context "when a floating bit was driven low before becoming an input" do
      before do
        address_bus[0x00] = 0xff
        address_bus[0x01] = 0x37
        address_bus[0x00] = 0x2f
      end

      specify { expect(address_bus[0x01] & 0x80).to eq(0) }
    end
  end

  it "overlays the ROM" do
    expect(address_bus[0xa000]).to eq(0x94)
  end

  context "when writing through an overlay" do
    before { address_bus[0xa000] = 0x20 }

    specify { expect(address_bus[0xa000]).to eq(0x94) }

    context "when the overlays are disabled" do
      # Disables all overlays
      before { address_bus.disable_overlays! }

      specify { expect(address_bus[0xa000]).to eq(0x20) }
    end
  end

  describe "the I/O 1 and 2 pages" do
    let(:vic_bank) { address_bus.vic.vic_bank }

    before do
      address_bus.ram.poke(0x3fff, 0xa5)
      vic_bank.peek(0x3fff)
    end

    it "reads the VIC's phi1 byte from I/O 1" do
      expect(address_bus[0xde00]).to eq(0xa5)
    end

    it "reads the VIC's phi1 byte from I/O 2" do
      expect(address_bus[0xdf80]).to eq(0xa5)
    end

    it "drops writes instead of storing them in the RAM below" do
      address_bus[0xde00] = 0x42
      expect(address_bus.ram[0xde00]).to eq(0x00)
    end

    context "when I/O is banked out" do
      before do
        address_bus.ram.poke(0xdf80, 0x5a)
        address_bus[0x01] = 0x34
      end

      specify { expect(address_bus[0xdf80]).to eq(0x5a) }
    end

    context "with a cartridge that reads I/O 1" do
      let(:crt) do
        instance_double(Badline::Storage::CRTFile, exrom: 1, game: 1, name: "TEST", chips: [])
      end
      let(:cartridge) do
        Class.new(Badline::Cartridge) do
          def readable_io_pages = [0xde]
          def peek(_addr) = 0x3c
          def install_chips(_chips); end
        end.new(crt)
      end

      before { address_bus.attach_cartridge(cartridge) }

      it "reads the cartridge's register in I/O 1" do
        expect(address_bus[0xde00]).to eq(0x3c)
      end

      it "leaves I/O 2 open" do
        expect(address_bus[0xdf80]).to eq(0xa5)
      end
    end
  end

  describe "the pot mux" do
    let(:paddles) { Badline::Input::Paddles.new }

    before do
      address_bus.control_ports.device1 = paddles
      paddles.move(-0x30, 0)
      address_bus[0xdc02] = 0xff
    end

    it "reads a port 1 paddle once CIA 1 PA6 selects it" do
      address_bus[0xdc00] = 0x40
      expect(address_bus[0xd419]).to eq(0x50)
    end

    it "leaves POTX floating while PA6 is low" do
      address_bus[0xdc00] = 0x80
      expect(address_bus[0xd419]).to eq(0xff)
    end
  end

  describe "the datasette lines" do
    let(:datasette) { address_bus.datasette }
    let(:tape) do
      instance_double(Badline::Storage::TAP, rewind: nil, end?: false, next_pulse: 1)
    end

    it "reads the cassette sense high with no key pressed" do
      expect(address_bus[0x01] & 0x10).to eq(0x10)
    end

    it "reads the cassette sense low while a key is pressed" do
      datasette.play!
      expect(address_bus[0x01] & 0x10).to eq(0x00)
    end

    it "leaves a driven sense line alone" do
      address_bus[0x00] = 0xff
      datasette.play!
      expect(address_bus[0x01] & 0x10).to eq(0x10)
    end

    it "runs the motor while bit 5 is low" do
      address_bus[0x01] = 0x17
      expect(datasette).to be_motor
    end

    it "stops the motor while bit 5 is high" do
      address_bus[0x01] = 0x37
      expect(datasette).not_to be_motor
    end

    it "pulses the CIA 1 flag line from the tape" do
      datasette.insert(tape)
      datasette.play!
      address_bus[0x01] = 0x17
      datasette.cycle!
      expect(address_bus.cia1.interrupt_status.flag?).to be(true)
    end
  end
end
