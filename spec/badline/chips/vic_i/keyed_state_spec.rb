# frozen_string_literal: true

require "spec_helper"
require_relative "../../../support/keyed_oracle"

# The VIC-I's keyed fields, its sound's included, against its positional
# save_state, which restores exactly: a VIC-20's VIC saved on any cycle of
# its boot once the text window opens, loaded into a fresh VIC-20's, saves the same positional state,
# with what the registers decode to, where the fetches end and the next
# event worked out again. The painter's repaint caches are left out, and
# reset to repaint every line on both.
module VICIKeyedSamples
  extend KeyedOracle

  # The voices on and the volume up part way through, and the colours
  # changed while a line goes out.
  WRITES = { 25_000 => [[0x0a, 0x87], [0x0b, 0xc0], [0x0c, 0xf3], [0x0d, 0xfe], [0x0e, 0x6f]],
             25_031 => [[0x0f, 0x2a]], 26_017 => [[0x0e, 0x9c], [0x0b, 0x40]] }.freeze

  module_function

  def comparable(vic)
    painter = vic.instance_variable_get(:@painter)
    painter.instance_variable_get(:@stale).fill(true)
    painter.instance_variable_get(:@memo_keys).fill(-1)
    positional(vic)
  end

  def check(machine)
    target = Badline::Vic20.new
    target.instance_variable_set(:@cycles, machine.cycles)
    target.sound_source.record(rate: 44_100)
    problems = keyed_round_trip(machine.vic, target.vic).report.lines(verbose: true)
    problems << "positional state differs" unless comparable(machine.vic) == comparable(target.vic)
    problems.map { |line| "cycle #{machine.cycles}: #{line}" }
  end

  # Every cycle around the writes, and every 97th elsewhere.
  def sampled?(cycle) = (cycle % 97).zero? || WRITES.keys.any? { |at| (cycle - at).abs < 40 }

  def boot
    @boot ||= begin
      machine = Badline::Vic20.new
      machine.sound_source.record(rate: 44_100)
      machine.run_cycles(515_000)
      problems = []
      30_000.times do |cycle|
        WRITES.fetch(cycle, []).each { |reg, value| machine.vic.poke(0x9000 + reg, value) }
        machine.cycle!
        problems.concat(check(machine)) if sampled?(cycle)
      end
      problems
    end
  end
end

describe Badline::Chips::VICI::KeyedState do
  it "restores the VIC and its sound through a VIC-20's boot, the text window open" do
    expect(VICIKeyedSamples.boot.first(5)).to be_empty
  end

  describe "a snapshot from another painter" do
    let(:machine) { Badline::Vic20.new.tap { |vic20| 3_000.times { vic20.cycle! } } }
    let(:target) { Badline::Vic20.new }

    it "leaves the line fields at power-on" do
      out = Badline::Snapshot::Keyed::Writer.new
      machine.vic.save_fields(out)
      out.int("line.layout", 99)
      target.vic.load_fields(Badline::Snapshot::Keyed::Reader.parse(out.section("BL-VICI")))
      expect(target.vic.instance_variable_get(:@painter).counts).to all(be_zero)
    end
  end
end
