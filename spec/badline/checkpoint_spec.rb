# frozen_string_literal: true

require "spec_helper"

describe Badline::Checkpoint do
  let(:computer) { Badline::Computer.new }
  let(:before) { described_class.take(computer) }

  def changed_by
    before
    yield
    described_class.take(computer).differences(before)
  end

  describe ".fnv1a" do
    it "starts from the offset basis" do
      expect(described_class.fnv1a([])).to eq(0x811c9dc5)
    end

    it "matches the reference FNV-1a over bytes" do
      expect(described_class.fnv1a("foobar".bytes)).to eq(0xbf9cf968)
    end
  end

  describe ".take" do
    it "records the cycle count" do
      3.times { computer.cycle! }
      expect(described_class.take(computer).cycle).to eq(3)
    end

    it "gives two fresh machines the same digests" do
      expect(described_class.take(Badline::Computer.new)).to eq(before)
    end

    it "notices a RAM write in the RAM alone" do
      expect(changed_by { computer.ram.poke(0x1234, 0x55) }).to eq(["ram"])
    end

    it "notices a colour RAM write in the colour RAM alone" do
      expect(changed_by { computer.address_bus.color_ram.poke(0xd900, 0x05) }).to eq(["color_ram"])
    end

    it "notices a CPU register" do
      expect(changed_by { computer.cpu.x = 0x42 }).to eq(["cpu"])
    end

    it "notices a VIC register" do
      expect(changed_by { computer.vic.poke(0xd020, 0x02) }).to eq(["vic"])
    end

    it "notices a CIA 2 register" do
      expect(changed_by { computer.cia2.poke(0xdd02, 0x3f) }).to eq(["cia2"])
    end

    it "notices a SID register" do
      expect(changed_by { computer.sid.poke(0xd418, 0x0f) }).to eq(["sid"])
    end

    it "notices the framebuffer" do
      expect(changed_by { computer.vic.display[1000] = 7 }).to eq(["display"])
    end

    it "leaves the VIC's collision registers set" do
      computer.vic.poke(0xd01e, 0x03)
      described_class.take(computer)
      expect(computer.vic.peek(0xd01e)).to eq(0x03)
    end

    it "leaves the CIA's interrupt flags set" do
      computer.cia1.flag!
      computer.cia1.cycle!
      described_class.take(computer)
      expect(computer.cia1.interrupt_status.value).to eq(0x10)
    end
  end

  describe ".parse" do
    it "reads back what #to_s writes" do
      expect(described_class.parse(before.to_s)).to eq(before)
    end

    it "rejects a line with a component missing" do
      expect { described_class.parse("100 cpu=00000000") }.to raise_error(ArgumentError, /ram/)
    end
  end

  describe "#to_s" do
    it "prints the cycle and eight-digit hex digests" do
      expect(described_class.new(5, Array.new(8, 0xab)).to_s)
        .to eq("5 cpu=000000ab ram=000000ab color_ram=000000ab display=000000ab " \
               "vic=000000ab cia1=000000ab cia2=000000ab sid=000000ab")
    end
  end

  describe "#differences" do
    it "names the components whose digests differ" do
      ours = described_class.new(5, [1, 2, 3, 4, 5, 6, 7, 8])
      theirs = described_class.new(5, [1, 0, 3, 4, 0, 6, 7, 8])
      expect(ours.differences(theirs)).to eq(%w[ram vic])
    end
  end
end
