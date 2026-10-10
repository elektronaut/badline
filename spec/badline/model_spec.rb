# frozen_string_literal: true

require "spec_helper"

describe Badline::Model do
  def chips(model) = [model.vic_model, model.cia_model, model.sid_model, model.region.name]

  def setup(sid_model) = Badline::Snapshot::C64Setup.of(Badline::AddressBus.new(sid_model:))

  it "builds the C64 by default" do
    expect(chips(described_class.named("c64"))).to eq(%i[mos6569 mos6526 mos6581 pal])
  end

  it "builds the C64C with the 8565, 6526As and the 8580" do
    expect(chips(described_class.named("c64c"))).to eq(%i[mos8565 mos6526a mos8580 pal])
  end

  it "builds the NTSC C64 with the 6567R8" do
    expect(chips(described_class.named("ntsc"))).to eq(%i[mos6569 mos6526 mos6581 ntsc])
  end

  it "builds the NTSC C64C with the 8562, 6526As and the 8580" do
    expect(chips(described_class.named("newntsc"))).to eq(%i[mos8565 mos6526a mos8580 ntsc])
  end

  it "builds the first NTSC C64 with the 6567R56A" do
    expect(chips(described_class.named("oldntsc"))).to eq(%i[mos6569 mos6526 mos6581 ntscold])
  end

  it "builds the Drean C64 with the 6572" do
    expect(chips(described_class.named("drean"))).to eq(%i[mos6569 mos6526 mos6581 drean])
  end

  it "builds the SX-64 with its own KERNAL and no datasette" do
    model = described_class.named("sx64")
    expect([*chips(model), model.kernal, model.datasette]).to eq([:mos6569, :mos6526, :mos6581, :pal, :sx64, false])
  end

  it "builds the PET 64 with its own KERNAL and board" do
    model = described_class.named("pet64")
    expect([*chips(model), model.kernal, model.board]).to eq(%i[mos6569 mos6526 mos6581 pal pet64 pet64])
  end

  it "builds the C64GS with a C64C's chips, its own ROMs and board, and no datasette" do
    model = described_class.named("c64gs")
    expect([*chips(model), model.kernal, model.board, model.datasette])
      .to eq([:mos8565, :mos6526a, :mos8580, :pal, :gs, :gs, false])
  end

  it "builds the MAX Machine on NTSC with its own board and a datasette" do
    model = described_class.named("ultimax")
    expect([*chips(model), model.board, model.datasette]).to eq([:mos6569, :mos6526, :mos6581, :ntscold, :max, true])
  end

  it "fails on a name it doesn't know" do
    expect { described_class.named("vic20") }.to raise_error(ArgumentError, /vic20/)
  end

  it "has a model for each name the options take" do
    expect(described_class::ALL.map(&:name)).to eq(Badline::Options::MODELS)
  end

  it "names the model a machine's chips make" do
    expect(described_class.of(setup(:mos6581))).to eq(described_class::C64)
  end

  it "names no model for chips that make none" do
    expect(described_class.of(setup(:mos8580))).to be_nil
  end
end
