# frozen_string_literal: true

require "spec_helper"

describe Badline::Machine do
  def chips(machine)
    [machine.vic.model, machine.cia1.model, machine.sound_source.model, machine.region.name]
  end

  it "builds a C64" do
    expect(described_class.build(:c64, model: "c64")).to be_a(Badline::Computer)
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

  it "refuses a family it can't build" do
    expect { described_class.build(:pet, model: "c64") }.to raise_error(ArgumentError, /pet/)
  end
end
