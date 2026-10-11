# frozen_string_literal: true

require "spec_helper"

describe Badline::Snapshot::Keyed::Recorder do
  subject(:recorder) { described_class.new("BL-CIA1") }

  let(:registers) { [1, 2] }

  before do
    recorder.word("ta.counter", 0xffff)
    recorder.ints_into("registers", registers)
    recorder.choice("model", %w[mos6526 mos6526a], "mos6526")
    recorder.optional_int("pos.t")
  end

  it "notes each read with its type and default" do
    expect(recorder.fields.map { |field| [field.key, field.type, field.default] })
      .to eq([["ta.counter", "word", 0xffff], ["registers", "ints", [1, 2]],
              ["model", "text: mos6526 mos6526a", "mos6526"], ["pos.t", "int, optional", nil]])
  end

  it "names the module" do
    expect(recorder.fields.map(&:module_name).uniq).to eq(["BL-CIA1"])
  end

  it "returns the default" do
    expect(recorder.byte("sp", 0xfd)).to eq(0xfd)
  end

  it "keeps a copy of an array's default" do
    registers[0] = 9
    expect(recorder.fields[1].default).to eq([1, 2])
  end

  it "reports nothing" do
    expect(recorder.report.lines(verbose: true)).to be_empty
  end
end
