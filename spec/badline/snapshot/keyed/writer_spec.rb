# frozen_string_literal: true

require "spec_helper"

describe Badline::Snapshot::Keyed::Writer do
  subject(:out) { described_class.new }

  def read(writer) = Badline::Snapshot::Keyed::Reader.parse(writer.section("BL-TEST"))

  it "writes a record as the key, the tag and the value, each length first" do
    expect(out.int("a", -1).to_s).to eq("\x01a\x01\x01\x01".b)
  end

  it "writes a BER length past 127" do
    expect(out.bytes("ram", [0] * 200).to_s.byteslice(0, 7)).to eq("\x03ram\x03\x81\x48".b)
  end

  it "reads back the largest values a native build can hold" do
    input = read(out.int("high", (2**62) - 1).int("low", -(2**62)))
    expect([input.int("high", 0), input.int("low", 0)]).to eq([(2**62) - 1, -(2**62)])
  end

  it "reads back each type" do
    input = read(out.bool("on", true).bytes("ram", [1, 255]).ints("regs", [-3, 7]).text("model", "mos6569"))
    expect([input.bool("on", false), input.bytes("ram", ""), input.ints("regs", []), input.text("model", "")])
      .to eq([true, "\x01\xff".b, [-3, 7], "mos6569"])
  end

  it "writes a binary String as bytes" do
    expect(read(out.bytes("image", "\x00\xfe".b)).bytes("image", "")).to eq("\x00\xfe".b)
  end

  it "reads text back as UTF-8" do
    expect(read(out.text("path", "æøå.d64")).text("path", "")).to eq("æøå.d64")
  end

  it "writes nothing for an optional int that is nil" do
    expect(out.optional_int("pos.t", nil).to_s).to be_empty
  end

  it "refuses a value a native build can't hold" do
    expect { out.int("cycles", 2**62) }.to raise_error(RangeError, /cycles .* too large/)
  end

  it "refuses one in a list too" do
    expect { out.ints("regs", [1, -(2**62) - 1]) }.to raise_error(RangeError, /regs/)
  end

  it "refuses a value that isn't an Integer" do
    expect { out.int("pc", nil) }.to raise_error(TypeError, /pc is not an Integer/)
  end

  it "refuses a key outside lower snake case with dots" do
    expect { out.int("ta.Counter", 1) }.to raise_error(ArgumentError, /not a snapshot key/)
  end

  it "refuses an empty part of a key" do
    expect { out.int("ta..counter", 1) }.to raise_error(ArgumentError, /not a snapshot key/)
  end

  it "makes a module in version 1.0, deflated" do
    section = out.int("a", 1).section("BL-CPU")
    expect([section.name, section.version, Zlib.inflate(section.data)]).to eq(["BL-CPU", "1.0", out.to_s])
  end
end
