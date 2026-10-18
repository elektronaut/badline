# frozen_string_literal: true

require "spec_helper"

describe Badline::Machine do
  def chips(machine)
    [machine.vic.model, machine.cia1.model, machine.sound_source.model, machine.region.name]
  end

  it "builds a C64" do
    expect(described_class.build(:c64, model: "c64")).to be_a(Badline::C64)
  end

  it "builds the model named" do
    expect(chips(described_class.build(:c64, model: "c64c"))).to eq(%i[mos8565 mos6526a mos8580 pal])
  end

  it "fits the SID given over the model's" do
    expect(chips(described_class.build(:c64, model: "c64c", sid_model: :mos6581)))
      .to eq(%i[mos8565 mos6526a mos6581 pal])
  end

  it "gives the model its KERNAL and datasette" do
    machine = described_class.build(:c64, model: "sx64")
    expect([machine.address_bus.kernal, machine.datasette.connected?]).to eq([:sx64, false])
  end

  it "gives the model its board" do
    expect(described_class.build(:c64, model: "pet64").address_bus.board).to eq(:pet64)
  end

  it "plugs in an REU of the size given" do
    expect(described_class.build(:c64, model: "c64", reu: 512).reu).not_to be_nil
  end

  it "builds a CBM-II of the model named" do
    machine = described_class.build(:cbm2, model: "720")
    expect([machine.class, machine.model.name]).to eq([Badline::CBM2, "720"])
  end

  it "builds a VIC-20 with the RAM expansion named" do
    machine = described_class.build(:vic20, model: "pal", ram: :"16k")
    expect([machine.class, machine.ram_configuration]).to eq([Badline::Vic20, :"16k"])
  end

  it "builds an unexpanded VIC-20 without RAM named" do
    expect(described_class.build(:vic20, model: "pal").ram_configuration).to eq(:unexpanded)
  end

  it "refuses a VIC-20 model it can't build" do
    expect { described_class.build(:vic20, model: "ntsc") }.to raise_error(ArgumentError, /ntsc/)
  end

  it "builds a C128 in C64 mode" do
    machine = described_class.build(:c128, model: "c128dcr")
    expect([machine.class, machine.mode, chips(machine)]).to eq([Badline::C128, :c64, %i[mos8566 mos6526a mos8580 pal]])
  end

  it "fits a C128 with the SID given over the model's" do
    expect(described_class.build(:c128, model: "c128", sid_model: :mos8580).sound_source.model).to eq(:mos8580)
  end

  it "builds a Plus/4 of the model named, with its RAM" do
    machine = described_class.build(:plus4, model: "c116")
    expect([machine.class, machine.model, machine.ram_kb]).to eq([Badline::Plus4, Badline::Plus4::Model::C16, 16])
  end

  it "builds a PET of the model named" do
    machine = described_class.build(:pet, model: "3032b")
    expect([machine.class, machine.model.name, machine.refresh_hz]).to eq([Badline::PET, "3032b", 60])
  end

  it "refuses a family it can't build" do
    expect { described_class.build(:c65, model: "c64") }.to raise_error(ArgumentError, /c65/)
  end

  describe ".for_options" do
    def options(*argv) = Badline::Options.parse(argv)

    it "builds a C128 in C128 mode" do
      expect(described_class.for_options(options("c128"), nil).mode).to eq(:c128)
    end

    it "holds C= through a C128's reset with --c64" do
      expect(described_class.for_options(options("c128", "--c64"), nil).keyboard.keys).to include(:cbm)
    end

    it "yields the RAM expansion it gives a VIC-20 for a program" do
      program = Tempfile.create(["game", ".prg"]).tap { |file| file.write("\x01\x12\x00\x00\x00") }.tap(&:close)
      expect { |line| described_class.for_options(options("vic20"), program.path, &line) }
        .to yield_with_args("RAM expansion: 8k")
    ensure
      File.delete(program.path)
    end

    it "gives a Plus/4 the RAM --ram names" do
      expect(described_class.for_options(options("plus4", "--model", "c16", "--ram", "64k"), nil).ram_kb).to eq(64)
    end

    it "fits a Plus/4 with the SID card --sid-card names" do
      expect(described_class.for_options(options("plus4", "--sid-card", "8580"), nil).sid_card.model).to eq(:mos8580)
    end

    it "puts the SID card where --sid-card-address says" do
      machine = described_class.for_options(options("plus4", "--sid-card", "6581", "--sid-card-address", "fe80"), nil)
      expect(machine.sid_card.address).to eq(0xfe80)
    end

    it "fits a Plus/4 with the RAM expansion --ram-expansion names" do
      machine = described_class.for_options(options("plus4", "--ram-expansion", "csory256"), nil)
      expect(machine.ram_expansion.kind).to eq(:csory256)
    end

    it "refuses media a Plus/4 doesn't take" do
      expect { described_class.for_options(options("plus4"), "tune.sid") }
        .to raise_error(Badline::Machine::Unsupported, %r{Plus/4})
    end

    it "gives a PET the RAM --ram names" do
      expect(described_class.for_options(options("pet", "--model", "3032", "--ram", "8k"), nil).ram_kb).to eq(8)
    end

    it "runs a PET's 60 Hz editor with --60hz" do
      machine = described_class.for_options(options("pet", "--60hz"), nil)
      expect([machine.refresh_hz, machine.model.editor(60)]).to eq([60, "pet/editor4-80-b-60hz.rom"])
    end

    it "fits a PET with the BASIC --basic names" do
      machine = described_class.for_options(options("pet", "--model", "2001", "--basic", "2"), nil)
      expect([machine.model.basic, machine.model.kernal, machine.model.editor(60)])
        .to eq(%w[pet/basic2.rom pet/kernal2.rom pet/editor2-n.rom])
    end

    it "refuses media a PET doesn't take" do
      expect { described_class.for_options(options("pet"), "tune.sid") }
        .to raise_error(Badline::Machine::Unsupported, /PET/)
    end

    it "refuses media a VIC-20 doesn't take" do
      expect { described_class.for_options(options("vic20"), "tune.sid") }
        .to raise_error(Badline::Machine::Unsupported, /VIC-20/)
    end
  end
end
