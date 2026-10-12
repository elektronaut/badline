# frozen_string_literal: true

require "spec_helper"
require "badline/plus4"

describe Badline::Plus4, "#ram_expansion" do
  subject(:machine) { described_class.new(ram_expansion: :hannes256) }

  # Writes +value+ to +addr+ in the bank $FD16 = +control+ selects, and
  # goes back to the standard bank.
  def write_in(control, addr, value)
    machine.poke(0xfd16, control)
    machine.poke(addr, value)
    machine.poke(0xfd16, 0xff)
  end

  def read_in(control, addr, target = machine)
    target.poke(0xfd16, control)
    target.peek(addr)
  end

  it "starts with the register's bits all set" do
    expect(machine.peek(0xfd16)).to eq(0xff)
  end

  it "reads back all eight bits of the register" do
    machine.poke(0xfd16, 0x5a)
    expect(machine.peek(0xfd16)).to eq(0x5a)
  end

  it "keeps a byte apart in each bank above the switch bound" do
    [0xfc, 0xfd, 0xfe, 0xff].each_with_index { |control, index| write_in(control, 0x4000, index) }
    expect([0xfc, 0xfd, 0xfe, 0xff].map { |control| read_in(control, 0x4000) }).to eq([0, 1, 2, 3])
  end

  it "shares the RAM below $4000 with bit 7 set" do
    write_in(0xfe, 0x3fff, 0x22)
    expect(machine.peek(0x3fff)).to eq(0x22)
  end

  it "banks from $1000 on with bit 7 clear" do
    write_in(0x7e, 0x1000, 0x22)
    expect([machine.peek(0x1000), read_in(0x7e, 0x0fff)]).to eq([0, 0])
  end

  it "banks the RAM under the ROMs and above the TED" do
    machine.poke(0xff3f, 0)
    write_in(0xfe, 0xffff, 0x22)
    expect([machine.peek(0xffff), read_in(0xfe, 0xffff)]).to eq([0, 0x22])
  end

  it "banks zero page and the stack with nothing" do
    write_in(0x7e, 0x01ff, 0x22)
    expect(machine.peek(0x01ff)).to eq(0x22)
  end

  it "has the user port at $FD10 alone" do
    machine.poke(0x0002, 0x66)
    expect([machine.peek(0xfd11), machine.peek(0xfd10)]).to eq([0x66, 0xff])
  end

  it "ignores bits 2 and 3 on the 256K" do
    write_in(0xf2, 0x4000, 0x22)
    expect(read_in(0xfe, 0x4000)).to eq(0x22)
  end

  it "has sixteen banks on the 1M, picked by bits 0-3" do
    expanded = described_class.new(ram_expansion: :hannes1m)
    expanded.poke(0xfd16, 0xf3)
    expanded.poke(0x4000, 0x22)
    expanded.poke(0xfd16, 0xff)
    expect(expanded.peek(0x4000)).to eq(0)
  end

  it "lets the TED fetch from the CPU's bank with bit 6 set" do
    write_in(0xfe, 0x4000, 0x22)
    machine.poke(0xfd16, 0xfe)
    expect([machine.bus.ted_fetch(0x4000), machine.bus.ted_pattern_fetch(0x4000, false)]).to eq([0x22, 0x22])
  end

  it "keeps the TED in the standard bank with bit 6 clear" do
    write_in(0xfe, 0x4000, 0x22)
    machine.poke(0xfd16, 0xbe)
    expect([machine.bus.ted_fetch(0x4000), machine.bus.ted_pattern_fetch(0x4000, false)]).to eq([0, 0])
  end

  it "goes back to the standard bank at reset" do
    machine.poke(0xfd16, 0x00)
    machine.reset!
    expect(machine.peek(0xfd16)).to eq(0xff)
  end

  it "fits 64K under the expansion on a C16" do
    expect(described_class.new(model: "c16", ram_expansion: :hannes256).ram_kb).to eq(64)
  end

  it "refuses less RAM than 64K" do
    expect { described_class.new(ram: 16, ram_expansion: :hannes256) }.to raise_error(ArgumentError, /64K/)
  end

  it "names itself for the pause menu" do
    expect(described_class.new(ram_expansion: :hannes1m).ram_expansion_label).to eq("HANNES, 1024 KB")
  end

  it "saves its register and its banks in a snapshot" do
    write_in(0xfe, 0x4000, 0x22)
    machine.poke(0xfd16, 0x7d)
    restored = machine.snapshot.load
    expect([restored.peek(0xfd16), read_in(0xfe, 0x4000, restored)]).to eq([0x7d, 0x22])
  end

  it "refuses a snapshot of a machine without the expansion" do
    image = described_class.new.snapshot
    expect { machine.restore(image) }.to raise_error(Badline::Snapshot::FormatError, /RAM expansion/)
  end

  context "with Csory's board" do
    subject(:machine) { described_class.new(ram_expansion: :csory256) }

    before { machine.poke(0xff3f, 0) }

    # Csory's mapping on, with block +block+ in window +window+.
    def csory(window, block)
      machine.poke(0xfd15, (window << 6) | block)
      machine.poke(0xfd16, 0xdf)
    end

    it "puts a 16K block in the window $FD15 picks" do
      csory(1, 9)
      machine.poke(0x4000, 0x22)
      csory(2, 9)
      expect(machine.peek(0x8000)).to eq(0x22)
    end

    it "keeps the standard bank's RAM in blocks 0-3" do
      machine.poke(0x7fff, 0x22)
      csory(2, 1)
      expect(machine.peek(0xbfff)).to eq(0x22)
    end

    it "shares Hannes's banks with the blocks above them" do
      write_in(0xfe, 0x4000, 0x22)
      csory(1, 5)
      expect(machine.peek(0x4000)).to eq(0x22)
    end

    it "switches the mapping on when bits 4 and 5 differ" do
      machine.poke(0xfd15, 0x45)
      machine.poke(0x4000, 0x22)
      machine.poke(0xfd16, 0xef)
      expect(machine.peek(0x4000)).to eq(0)
    end

    it "can't read Csory's latch back" do
      machine.poke(0xfd15, 0x45)
      machine.poke(0x0002, 0x66)
      expect(machine.peek(0xfd15)).to eq(0x66)
    end

    it "lets the TED fetch the KERNAL from the high ROM in any bank" do
      machine.poke(0xfdd4, 0)
      expect(machine.bus.ted_pattern_fetch(0xd000, true)).to eq(described_class.new.bus.ted_pattern_fetch(0xd000, true))
    end

    it "saves Csory's latch in a snapshot" do
      csory(1, 9)
      machine.poke(0x4000, 0x22)
      expect(machine.snapshot.load.peek(0x4000)).to eq(0x22)
    end
  end
end
