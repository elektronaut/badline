# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require_relative "../../support/kim_tape_signal"

describe Badline::KIM1::Tape do
  subject(:deck) { described_class.new(clock) }

  let(:clock) { Struct.new(:cycles).new(1_000) }

  # PB7 as the deck drives it at each of `times`, in microseconds from
  # when PLAY went down.
  def levels_at(times)
    start = clock.cycles
    times.map do |time|
      clock.cycles = start + time
      deck.input >> 7
    end
  end

  # Toggles PB7 at each of `times` from when RECORD went down.
  def toggle_at(times)
    start = clock.cycles
    times.each_with_index do |time, index|
      clock.cycles = start + time
      deck.output(index.even? ? 0x00 : 0x80)
    end
  end

  # Plays the tape `time` microseconds on, and stops.
  def wind_to(time)
    deck.play
    clock.cycles += time
    deck.stop
  end

  describe "playing" do
    before { deck.insert(Badline::Storage::KIMTape.new(crossings: [0, 135, 270, 405, 540, 748, 956, 1164, 1372])) }

    it "drives PB7 from the tape's edges" do
      deck.play
      expect(levels_at([0, 100, 400, 500, 1_400])).to eq([1, 0, 0, 1, 1])
    end

    it "holds PB7 high while stopped" do
      deck.play
      levels_at([100])
      deck.stop
      expect(deck.input).to eq(0xff)
    end

    it "carries on from where it stopped" do
      deck.play
      levels_at([200])
      deck.stop
      deck.play
      expect([deck.position, levels_at([0, 300])]).to eq([200, [0, 1]])
    end

    it "winds back to the start" do
      deck.play
      levels_at([500])
      deck.rewind
      expect(deck.position).to eq(0)
    end
  end

  describe "recording" do
    it "puts each change of PB7 on the tape" do
      deck.record
      toggle_at([10, 145, 280])
      expect(deck.tape.crossings).to eq([10, 145, 280])
    end

    it "ignores writes that leave PB7 alone" do
      deck.record
      toggle_at([10])
      deck.output(0x01)
      expect(deck.tape.crossings).to eq([10])
    end

    it "records over the rest of the tape" do
      deck.insert(Badline::Storage::KIMTape.new(crossings: [100, 200, 300]))
      wind_to(150)
      deck.record
      toggle_at([50])
      expect(deck.tape.crossings).to eq([100, 200])
    end

    context "with a tape from a file" do
      let(:dir) { Dir.mktmpdir }
      let(:path) { File.join(dir, "dump.wav") }

      after { FileUtils.remove_entry(dir) }

      it "writes the tape to the file when it stops" do
        deck.insert(Badline::Storage::KIMTape.create(path))
        deck.record
        toggle_at([1_000, 1_135, 1_270])
        deck.stop
        expect(Badline::Storage::KIMTape.read(path).crossings.length).to eq(3)
      end
    end

    it "leaves an ejected tape blank" do
      deck.record
      toggle_at([10])
      deck.eject
      expect([deck.recording?, deck.tape.crossings]).to eq([false, []])
    end
  end

  describe "on the KIM-1" do
    let(:kim) { Badline::KIM1.new }

    # Jumps to `address` once the monitor runs, as GO would.
    def go(address)
      kim.run_cycles(Badline::KIM1::BOOT_CYCLES)
      kim.cycle! until kim.cpu.boundary?
      kim.cpu.program_counter = address
    end

    # The User Manual's appendix E gives the tones; DUMPT ($1800) times
    # each half period with U2's timer.
    it "records DUMPT's tones, 3,676 Hz and 2,427 Hz" do
      go(0x1800)
      kim.tape.record
      kim.run_cycles(8_000)
      half_periods = kim.tape.tape.crossings.each_cons(2).map { |from, to| to - from }
      expect(half_periods.drop(1).tally.keys).to all(be_between(135, 139).or(be_between(203, 209)))
    end

    # Plays the tape until LOADT has stored its verdict in $FA.
    def play_until_loaded
      kim.poke(0xfa, 0x55)
      kim.tape.play
      kim.run_cycles(10_000) while kim.peek(0xfa) == 0x55 && kim.cycles < 1_000_000
    end

    # LOADT ($1873) ends by showing 0000 for a good checksum and FFFF for
    # a bad one, from $FA-$FB.
    it "loads a block through LOADT", :slow do
      chars = KIMTapeSignal.block(0x01, 0x0200, [0xa9, 0x42, 0x60])
      kim.tape.insert(Badline::Storage::KIMTape.new(crossings: KIMTapeSignal.crossings(chars)))
      go(0x1873)
      play_until_loaded
      expect([kim.peek(0xfa), kim.peek(0x0200), kim.peek(0x0201), kim.peek(0x0202)]).to eq([0x00, 0xa9, 0x42, 0x60])
    end
  end
end
