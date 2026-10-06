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

  it "plugs in an REU of the size given" do
    expect(described_class.build(:c64, model: "c64", reu: 512).reu).not_to be_nil
  end

  it "refuses a family it can't build" do
    expect { described_class.build(:vic20, model: "c64") }.to raise_error(ArgumentError, /vic20/)
  end
end
