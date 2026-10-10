# frozen_string_literal: true

require "spec_helper"

describe Badline::Vic20Checkpoint do
  let(:machine) { Badline::Vic20.new }
  let(:before) { described_class.take(machine) }

  def changed_by
    before
    yield
    described_class.take(machine).differences(before)
  end

  describe ".take" do
    it "records the cycle count" do
      3.times { machine.cycle! }
      expect(described_class.take(machine).cycle).to eq(3)
    end

    it "gives two fresh machines the same digests" do
      expect(described_class.take(Badline::Vic20.new)).to eq(before)
    end

    it "notices a RAM write in the RAM alone" do
      expect(changed_by { machine.ram.poke(0x1234, 0x55) }).to eq(["ram"])
    end

    it "notices a colour RAM write in the colour RAM alone" do
      expect(changed_by { machine.bus.color_ram.poke(0x9500, 0x05) }).to eq(["color_ram"])
    end

    it "notices a VIC register" do
      expect(changed_by { machine.vic.poke(0x900f, 0x2a) }).to include("vic")
    end

    it "notices a VIA 1 register in VIA 1 alone" do
      expect(changed_by { machine.via1.poke(0x9112, 0x3f) }).to eq(["via1"])
    end

    it "notices a VIA 2 register in VIA 2 alone" do
      expect(changed_by { machine.via2.poke(0x912e, 0xc0) }).to eq(["via2"])
    end

    it "notices the sound's volume" do
      expect(changed_by { machine.sound.write(0x0e, 0x0f) }).to eq(["sound"])
    end
  end

  describe ".parse" do
    it "reads back what #to_s writes" do
      expect(described_class.parse(before.to_s)).to eq(before)
    end

    it "rejects a C64's line" do
      expect { described_class.parse(Badline::Checkpoint.take(Badline::Computer.new).to_s) }
        .to raise_error(ArgumentError, /via1/)
    end
  end
end
