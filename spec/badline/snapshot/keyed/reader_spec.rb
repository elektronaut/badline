# frozen_string_literal: true

require "spec_helper"

describe Badline::Snapshot::Keyed::Reader do
  subject(:input) { described_class.parse(out.section("BL-TEST")) }

  let(:out) do
    Badline::Snapshot::Keyed::Writer.new.int("pc", 0x1fce2).bool("nmi", true).ints("regs", [1, 2, 3])
                                    .bytes("ram", [7, 8]).text("model", "mos9999").int("later", 5)
  end

  def adjusted = input.report.adjusted

  it "reads a record that is there" do
    expect(input.int("pc", 0)).to eq(0x1fce2)
  end

  it "returns the default for a key that isn't there" do
    expect([input.int("sp", 0xfd), input.bool("irq", false), input.text("mode", "c64")]).to eq([0xfd, false, "c64"])
  end

  it "returns nil for an optional int that isn't there" do
    expect(input.optional_int("pos.t")).to be_nil
  end

  context "when a record has another type than the one read" do
    before { input.int("nmi", 4) }

    it { expect(input.int("nmi", 4)).to eq(4) }
    it { expect(adjusted).to eq(["nmi is not an int, left at its default"]) }
  end

  context "when an int is wider than its latch" do
    before { input.word("pc", 0) }

    it { expect(input.word("pc", 0)).to eq(0xfce2) }
    it { expect(adjusted).to eq(["pc 130274 is wider than its latch, masked to 64738"]) }
  end

  it "leaves a value that fits its latch alone" do
    input.masked("later", 0, 0x07)
    expect(adjusted).to be_empty
  end

  context "when a list is shorter than the array it reads into" do
    let(:array) { [9, 9, 9, 9] }

    before { input.ints_into("regs", array) }

    it { expect(array).to eq([1, 2, 3, 9]) }
    it { expect(adjusted).to eq(["regs holds 3 values where 4 fit, the rest left as they were"]) }
  end

  context "when bytes are longer than the array they read into" do
    let(:array) { [0] }

    before { input.bytes_into("ram", array) }

    it { expect(array).to eq([7]) }
    it { expect(adjusted).to eq(["ram holds 2 values where 1 fit, the rest cut"]) }
  end

  it "leaves an array alone when its record isn't there" do
    expect(input.ints_into("other", [4, 5])).to eq([4, 5])
  end

  context "when text names none of the choices" do
    before { input.choice("model", %w[mos6569 mos8565], "mos6569") }

    it { expect(input.choice("model", %w[mos6569 mos8565], "mos6569")).to eq("mos6569") }
    it { expect(adjusted.first).to eq('model "mos9999" is not one of mos6569, mos8565, left at mos6569') }
  end

  it "reads text that names a choice" do
    expect(input.choice("model", %w[mos9999], "x")).to eq("mos9999")
  end

  context "when a key appears twice" do
    let(:out) { Badline::Snapshot::Keyed::Writer.new.int("a", 1).bool("a", true) }

    it { expect([input.int("a", 0), input.bool("a", false)]).to eq([0, true]) }
    it { expect(adjusted.first).to eq("a appears more than once, the last one counts") }
  end

  it "reports what a unit adds" do
    input.adjust("line in progress from another renderer, restarted")
    expect(adjusted).to eq(["line in progress from another renderer, restarted"])
  end

  it "lists the keys nothing read" do
    input.int("pc", 0)
    expect(input.report.unknown).to eq(%w[nmi regs ram model later])
  end

  it "skips a record of a type it doesn't know" do
    payload = "\x01x\x09\x03abc".b + Badline::Snapshot::Keyed::Writer.new.int("a", 2).to_s
    reader = described_class.new("BL-TEST", payload)
    expect([reader.int("a", 0), reader.report.unknown_tags]).to eq([2, 1])
  end

  it "reports a missing module" do
    expect(described_class.missing("BL-VIC").report.lines).to eq(["BL-VIC is missing, left at power-on"])
  end

  describe "the report's lines" do
    before { input.word("pc", 0) }

    it "leave unknown fields out" do
      expect(input.report.lines).to eq(["BL-TEST: pc 130274 is wider than its latch, masked to 64738"])
    end

    it "name unknown fields when verbose" do
      expect(input.report.lines(verbose: true).last).to eq("BL-TEST: 5 unknown field(s): nmi, regs, ram, model, later")
    end
  end

  describe "a module it can't read" do
    let(:section) { out.section("BL-TEST") }
    let(:error) { Badline::Snapshot::FormatError }

    it "refuses another major version" do
      expect { described_class.parse(section.with(major: 2)) }.to raise_error(error, /newer badline's encoding/)
    end

    it "fails on a damaged payload" do
      expect { described_class.parse(section.with(data: "damaged".b)) }.to raise_error(error, /damaged/)
    end

    it "fails on a record cut short" do
      expect { described_class.new("BL-TEST", out.to_s.byteslice(0, 5)) }.to raise_error(error, /ends early/)
    end

    it "fails on a number too large for a native build" do
      expect { described_class.new("BL-TEST", "\x01a\x01\x0a#{"\xff" * 9}\x7f".b) }.to raise_error(error, /too large/)
    end

    it "fails on a list longer than its record" do
      expect { described_class.new("BL-TEST", "\x01a\x04\x01\x05".b) }.to raise_error(error, /list of 5/)
    end
  end
end
