# frozen_string_literal: true

require "spec_helper"
require_relative "../../../support/keyed_oracle"
require_relative "../../../support/snapshot_scenarios"

# The CIA's keyed fields, saved again the same: a CIA saved on any cycle,
# loaded into a fresh one, saves the same fields, with the fast-path flags
# and the TOD divider worked out again.
module CIAKeyedSamples
  extend KeyedOracle

  module_function

  # Round trips `cia` into a fresh CIA built as `build` builds one, and
  # returns what differs.
  def check(cia, fresh, cycle)
    problems = keyed_round_trip(cia, fresh).report.lines(verbose: true)
    problems << "saves other fields" unless saved_fields(cia) == saved_fields(fresh)
    problems.map { |line| "cycle #{cycle}: #{line}" }
  end

  def demo(model)
    @demo ||= {}
    @demo[model] ||= begin
      machine = Badline::C64.new(cia_model: model)
      machine.load_prg(SnapshotScenarios::DEMO_PRG)
      machine.cpu.program_counter = SnapshotScenarios::DEMO_START
      Array.new(20_000) do
        machine.cycle!
        [machine.cia1, machine.cia2].flat_map do |cia|
          check(cia, Badline::Chips::CIA.new(start: cia.start, model:), machine.cycles)
        end
      end.flatten
    end
  end

  # Timer A shifting a byte out of the serial port, timer B counting its
  # underflows, the TOD clock fed fast with its alarm due, and the
  # interrupt register read now and then.
  WRITES = {
    0 => [[0x0d, 0x8f], [0x04, 0x07], [0x05, 0x00], [0x06, 0x02], [0x07, 0x00], [0x0e, 0x51], [0x0f, 0x51]],
    20 => [[0x0c, 0xa5]],
    40 => [[0x0f, 0xd1], [0x0b, 0x01], [0x0a, 0x00], [0x09, 0x00], [0x08, 0x05], [0x0f, 0x51]],
    60 => [[0x0b, 0x01], [0x0a, 0x00], [0x09, 0x00], [0x08, 0x00]],
    300 => [[0x0c, 0x3c]],
    900 => [[0x0e, 0x19]],
    1400 => [[0x0e, 0x81], [0x0f, 0x08]]
  }.freeze

  def scripted(model)
    @scripted ||= {}
    @scripted[model] ||= begin
      cia = Badline::Chips::CIA.new(start: 0xdc00, model:, tod_hz: 100_000)
      Array.new(3_000) do |cycle|
        WRITES.fetch(cycle, []).each { |reg, value| cia.poke(0xdc00 + reg, value) }
        cia.peek(0xdc0d) if (cycle % 37).zero?
        cia.peek(0xdc08) if (cycle % 211).zero?
        cia.cycle!
        check(cia, Badline::Chips::CIA.new(start: 0xdc00, model:, tod_hz: 100_000), cycle)
      end.flatten
    end
  end
end

describe Badline::Chips::CIA::KeyedState do
  it "restores both CIAs on every cycle of the demo" do
    expect(CIAKeyedSamples.demo(:mos6526).first(5)).to be_empty
  end

  %i[mos6526 mos6526a].each do |model|
    context "with the #{model}" do
      it "restores a CIA shifting, counting, ticking and read on every cycle" do
        expect(CIAKeyedSamples.scripted(model).first(5)).to be_empty
      end
    end
  end

  describe "the TOD divider" do
    let(:cia) { Badline::Chips::CIA.new(start: 0xdc00).tap { |chip| chip.poke(0xdc0e, 0x80) } }
    let(:fresh) { Badline::Chips::CIA.new(start: 0xdc00) }

    it "follows CRA bit 7" do
      CIAKeyedSamples.keyed_round_trip(cia, fresh)
      expect(fresh.time_of_day.instance_variable_get(:@match)).to eq(4)
    end
  end
end
