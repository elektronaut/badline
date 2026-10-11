# frozen_string_literal: true

require "spec_helper"

# A C64 with a second and a third SID, as the SID player fits them, saved
# mid-note and loaded into a new machine. The extra SIDs clock ahead of the
# machine, as the player clocks them.
module ExtraSIDSamples
  module_function

  def machine
    Badline::C64.new.tap do |computer|
      bus = computer.address_bus
      bus.add_sid(Badline::Chips::SID.new(model: :mos8580, at: 0xd420))
      bus.add_sid(Badline::Chips::SID.new(at: 0xde00))
      [0xd400, 0xd420, 0xde00].each_with_index { |base, index| play(bus, base, index) }
      run(computer, 3_001)
    end
  end

  # A pulse note on voice 1 and a noise one on voice 3, filtered, a
  # different pitch on each SID.
  def play(bus, base, index)
    { 0x00 => 0x31 + index, 0x01 => 0x1c, 0x02 => 0x00, 0x03 => 0x08, 0x05 => 0x09, 0x06 => 0xf0,
      0x04 => 0x41, 0x0f => 0x40 + index, 0x13 => 0x22, 0x14 => 0xa8, 0x12 => 0x81,
      0x16 => 0x60, 0x17 => 0xf5, 0x18 => 0x1f }.each { |offset, value| bus.poke(base + offset, value) }
  end

  def run(computer, cycles)
    extras = computer.address_bus.extra_sids
    cycles.times do
      extras.each(&:cycle!)
      computer.cycle!
    end
    computer
  end

  def image = @image ||= machine.snapshot

  # Each module's records, inflated, by name.
  def records(image) = image.sections.to_h { |section| [section.name, Zlib.inflate(section.data)] }

  # `image` with the BL-SID2 module the block writes in place of its own.
  def with_second(image, &)
    second = Badline::Snapshot::Keyed.section("BL-SID2", &)
    sections = image.sections.map { |section| section.name == "BL-SID2" ? second : section }
    Badline::Snapshot::Image.new(Badline::Snapshot::Container.new(sections))
  end
end

describe Badline::C64::Bus, "#load_extra_sid_modules" do
  let(:image) { ExtraSIDSamples.image }

  def fitted(computer) = computer.address_bus.extra_sids.map { |sid| [sid.start, sid.model] }

  def load(image)
    lines = []
    computer = image.load { |line| lines << line }
    [computer, lines]
  end

  it "saves each extra SID in a module of its own" do
    expect(image.sections.map(&:name)).to include("BL-SID2", "BL-SID3")
  end

  it "fits the extra SIDs a snapshot holds into a new machine" do
    expect(fitted(load(image).first)).to eq([[0xd420, :mos8580], [0xde00, :mos6581]])
  end

  it "loads them without a word" do
    expect(load(image).last).to be_empty
  end

  it "saves again what it loaded" do
    loaded = load(image).first
    expect(ExtraSIDSamples.records(loaded.snapshot)).to eq(ExtraSIDSamples.records(image))
  end

  # The SIDs' pitch, pulse width, envelope rates and filter settings are
  # worked out again from the registers.
  it "plays on as the saved machine does" do
    original = ExtraSIDSamples.machine
    loaded = load(original.snapshot).first
    [original, loaded].each { |computer| ExtraSIDSamples.run(computer, 20_000) }
    expect(ExtraSIDSamples.records(loaded.snapshot)).to eq(ExtraSIDSamples.records(original.snapshot))
  end

  it "keeps a SID already fitted at the same address" do
    computer = Badline::C64.new
    second = Badline::Chips::SID.new(at: 0xd420)
    computer.address_bus.add_sid(second)
    computer.restore(image)
    expect(computer.address_bus.extra_sids.first).to equal(second)
  end

  it "takes out the extra SIDs a snapshot hasn't" do
    computer = image.load
    computer.restore(Badline::C64.new.snapshot)
    expect(fitted(computer)).to be_empty
  end

  it "gives the first SID its mirror back once the second comes out" do
    computer = image.load
    computer.restore(Badline::C64.new.snapshot)
    computer.address_bus.poke(0xd421, 0x12)
    expect(computer.sid.register(0x01)).to eq(0x12)
  end

  it "leaves out a SID at an address none fits at" do
    damaged = ExtraSIDSamples.with_second(image) { |out| out.int("address", 0xd410) }
    expect(fitted(load(damaged).first)).to eq([[0xde00, :mos6581]])
  end

  it "says so" do
    damaged = ExtraSIDSamples.with_second(image) { |out| out.int("address", 0xd410) }
    expect(load(damaged).last).to eq(["BL-SID2: no SID fits at $d410, so it's left out"])
  end
end
