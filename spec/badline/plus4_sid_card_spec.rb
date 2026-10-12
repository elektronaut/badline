# frozen_string_literal: true

require "spec_helper"
require "badline/plus4"

describe Badline::Plus4, "#sid_card" do
  subject(:machine) { described_class.new(sid_card: :mos6581) }

  # One PAL frame of TED cycles.
  let(:frame) { 57 * 312 }

  # Voice 3's sawtooth at frequency $0100 from a reset oscillator, on a
  # SID at +base+.
  def start_sawtooth(target, base = 0xfd40)
    target.poke(base + 0x0e, 0x00)
    target.poke(base + 0x0f, 0x01)
    target.poke(base + 0x12, 0x08)
    target.poke(base + 0x12, 0x20)
  end

  it "puts a SID at $FD40-$FD5F" do
    machine.poke(0xfd58, 0x0f)
    expect(machine.sid_card.sid.register(0x18)).to eq(0x0f)
  end

  # A C64's clock would read 76 after the frame, and xplus4's SID card,
  # which counts the CPU's double clock, reads 138.
  it "clocks the SID once a TED cycle" do
    start_sawtooth(machine)
    machine.run_cycles(frame)
    expect(machine.peek(0xfd5b)).to eq(69)
  end

  it "doesn't repeat the card's registers above $FD5F" do
    machine.poke(0x0002, 0x66)
    machine.peek(0x0002)
    expect(machine.peek(0xfd7b)).to eq(0x66)
  end

  it "leaves $FD40-$FD5F open without one" do
    plain = described_class.new
    start_sawtooth(plain)
    plain.run_cycles(frame)
    expect(plain.peek(0xfd5b)).to eq(plain.bus.data)
  end

  it "fits one on a C16" do
    c16 = described_class.new(model: "c16", sid_card: :mos8580)
    expect(c16.sid_card.model).to eq(:mos8580)
  end

  it "resets the card's SID with the machine" do
    machine.poke(0xfd58, 0x0f)
    machine.reset!
    expect(machine.sid_card.sid.register(0x18)).to eq(0)
  end

  # Voice 3's sawtooth gated at full volume, sustained.
  def play_tone
    { 0xfd58 => 0x0f, 0xfd4f => 0x20, 0xfd53 => 0x00, 0xfd54 => 0xf0, 0xfd52 => 0x21 }
      .each { |addr, value| machine.poke(addr, value) }
  end

  it "plays the TED and the SID together" do
    machine.sound_source.record(rate: 44_100, clock_hz: machine.timing.clock_hz)
    play_tone
    machine.run_cycles(frame)
    expect(machine.sound_source.drain_samples.uniq.size).to be > 100
  end

  it "saves the card's SID and its model in a snapshot" do
    machine.poke(0xfd58, 0x0f)
    restored = machine.snapshot.load
    expect([restored.sid_card.model, restored.sid_card.sid.register(0x18)]).to eq([:mos6581, 0x0f])
  end

  it "runs on from a snapshot as the saved machine does" do
    start_sawtooth(machine)
    restored = machine.snapshot.load
    [machine, restored].each { |each_machine| each_machine.run_cycles(1_000) }
    expect(restored.peek(0xfd5b)).to eq(machine.peek(0xfd5b))
  end

  it "refuses a snapshot of a machine without the card" do
    image = described_class.new.snapshot
    expect { machine.restore(image) }.to raise_error(Badline::Snapshot::FormatError, /SID card/)
  end

  it "fits a card only at $FD40 or $FE80" do
    expect { described_class.new(sid_card: :mos6581, sid_card_address: 0xfe00) }
      .to raise_error(ArgumentError, /\$FE00/)
  end

  context "with the card at $FE80" do
    subject(:machine) { described_class.new(sid_card: :mos6581, sid_card_address: 0xfe80, tcbm: true) }

    it "puts the SID at $FE80-$FE9F" do
      machine.poke(0xfe98, 0x0f)
      expect(machine.sid_card.sid.register(0x18)).to eq(0x0f)
    end

    it "clocks the SID there" do
      start_sawtooth(machine, 0xfe80)
      machine.run_cycles(frame)
      expect(machine.peek(0xfe9b)).to eq(69)
    end

    it "leaves $FD40-$FD5F open" do
      machine.poke(0xfd58, 0x0f)
      expect(machine.sid_card.sid.register(0x18)).to eq(0)
    end

    it "doesn't repeat the card's registers around it" do
      machine.poke(0xfeb8, 0x0f)
      machine.poke(0xfe78, 0x0f)
      expect(machine.sid_card.sid.register(0x18)).to eq(0)
    end

    it "leaves the TCBM interface's TIAs where they are" do
      machine.poke(0xfee3, 0xff)
      expect(machine.tias[0].peek(0xfee3)).to eq(0xff)
    end

    it "keeps its address in a snapshot" do
      expect(machine.snapshot.load.sid_card.address).to eq(0xfe80)
    end

    it "refuses a snapshot of a card at $FD40" do
      image = described_class.new(sid_card: :mos6581, tcbm: true).snapshot
      expect { machine.restore(image) }.to raise_error(Badline::Snapshot::FormatError, /\$FD40/)
    end
  end
end
