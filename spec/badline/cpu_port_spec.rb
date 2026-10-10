# frozen_string_literal: true

require "spec_helper"

describe Badline::CPUPort do
  let(:datasette) { Badline::Datasette.new }
  let(:port) { described_class.new(datasette, pullups: 0x17, floating: 0xc8) }
  let(:changes) { [] }

  before { port.on_change { changes << port.value } }

  it "reads the pull-ups and bit 5 low at power-on" do
    expect(port.value).to eq(0x17)
  end

  it "calls the change handler on a write" do
    port.write_ddr(0x2f)
    expect(changes).to eq([0x10])
  end

  context "when a floating bit was driven high before a reset" do
    before do
      port.write_ddr(0xff)
      port.write_data(0xb7)
      port.reset!
    end

    it "keeps its charge" do
      expect(port.value).to eq(0x97)
    end

    it "clears the direction and output registers" do
      expect([port.ddr, port.data]).to eq([0x00, 0x00])
    end
  end

  it "runs the motor while bit 5 is driven low" do
    port.write_ddr(0x2f)
    expect(datasette.motor?).to be(true)
  end

  it "stops the motor while bit 5 is driven high" do
    port.write_ddr(0x2f)
    port.write_data(0x20)
    expect(datasette.motor?).to be(false)
  end

  it "reads the tape sense low while PLAY is down" do
    datasette.on_sense_change { port.refresh }
    datasette.play!
    expect(port.value & 0x10).to eq(0)
  end

  context "when loaded from a snapshot" do
    before { port.load(0x2f, 0x37, 0x80) }

    it "reads the registers back" do
      expect([port.ddr, port.data, port.floating, port.value]).to eq([0x2f, 0x37, 0x80, 0xb7])
    end

    it "leaves the change handler alone" do
      expect(changes).to be_empty
    end
  end

  describe "the 8502's CAPS LOCK pin" do
    let(:port) { described_class.new(datasette, pullups: 0x17, floating: 0x88, caps_lock: 0x40) }

    it "reads high while the key is up" do
      expect(port.value).to eq(0x57)
    end

    it "reads low while the key is down" do
      port.caps_lock = true
      expect(port.value).to eq(0x17)
    end
  end
end
