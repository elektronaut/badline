# frozen_string_literal: true

require "spec_helper"
require_relative "../../../support/keyed_oracle"

# The datasette's keyed fields, saved again the same.
describe Badline::Drives::Datasette::KeyedState do
  include KeyedOracle

  let(:dir) { Dir.mktmpdir }
  let(:path) do
    pulses = Array.new(400) { |i| i.even? ? 0x30 : 0x42 }
    File.join(dir, "noise.tap").tap do |file|
      File.binwrite(file, "C64-TAPE-RAW".b + [1, 0, 0, 0, pulses.length].pack("C4V") + pulses.pack("C*"))
    end
  end
  let(:saved) do
    Badline::Drives::Datasette.new(Badline::Storage::TAP.new(path)).tap do |datasette|
      datasette.play!
      datasette.motor = true
      5001.times { datasette.cycle! }
    end
  end

  # A version 2 tape's half waves on a datasette that times the read
  # line's level, part way through the first high half.
  let(:level) do
    tape = Badline::Storage::TAP.new("", bytes: "C16-TAPE-RAW".bytes + [2, 2, 0, 0, 6, 0, 0, 0] + ([0x30, 0x52] * 3))
    Badline::Drives::Datasette.new(tape, level: true).tap do |deck|
      deck.play!
      deck.motor = true
      401.times { deck.cycle! }
    end
  end

  it "puts the tape back in where it had played to, from the bytes it holds" do
    target = Badline::Drives::Datasette.new
    keyed_round_trip(saved, target)
    File.delete(path)
    expect(saved_fields(target)).to eq(saved_fields(saved))
  end

  it "puts a level datasette back where the read line rises in a version 2 tape's half waves" do
    target = Badline::Drives::Datasette.new(level: true).tap { |deck| keyed_round_trip(level, deck) }
    expect([saved_fields(target), target.read_high?]).to eq([saved_fields(level), level.read_high?])
  end

  describe "a datasette recording" do
    # Partway through a pulse: the write line low for 50 cycles since the
    # rising edge that ended the pulse before.
    let(:recording) do
      blank = Badline::Storage::TAP.create(File.join(dir, "saved.tap"), platform: 0)
      Badline::Drives::Datasette.new(blank).tap do |deck|
        deck.record!
        deck.motor = true
        [100, 50].each { |cycles| finish_pulse(deck, cycles) }
        deck.write_line = false
        50.times { deck.cycle! }
      end
    end

    def finish_pulse(deck, cycles)
      deck.write_line = false
      cycles.times { deck.cycle! }
      deck.write_line = true
    end

    def ends_the_pulse(deck)
      30.times { deck.cycle! }
      deck.write_line = true
      deck.tape.bytes
    end

    it "goes on recording the pulse in flight" do
      target = Badline::Drives::Datasette.new.tap { |deck| keyed_round_trip(recording, deck) }
      expect(ends_the_pulse(target)).to eq(ends_the_pulse(recording))
    end

    it "keeps the keys down for the recording" do
      target = Badline::Drives::Datasette.new.tap { |deck| keyed_round_trip(recording, deck) }
      expect([target.recording?, saved_fields(target)]).to eq([true, saved_fields(recording)])
    end
  end

  it "takes the tape out when the module holds none" do
    target = Badline::Drives::Datasette.new(Badline::Storage::TAP.new(path))
    keyed_round_trip(Badline::Drives::Datasette.new, target)
    expect(target.tape).to be_nil
  end
end
