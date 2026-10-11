# frozen_string_literal: true

require "spec_helper"
require_relative "../../../support/keyed_oracle"

# The VIA's keyed fields, saved again the same: a VIA saved on any cycle,
# loaded into a fresh one, saves the same fields, with whether the shift
# register clocks off timer 2 worked out from the ACR.
module VIAKeyedSamples
  extend KeyedOracle

  module_function

  def check(via, cycle)
    fresh = Badline::Chips::VIA.new(start: via.start)
    problems = keyed_round_trip(via, fresh).report.lines(verbose: true)
    problems << "saves other fields" unless saved_fields(via) == saved_fields(fresh)
    problems.map { |line| "cycle #{cycle}: #{line}" }
  end

  # Both VIAs of a VIC-20 booting.
  def vic20
    @vic20 ||= begin
      machine = Badline::Vic20.new
      Array.new(10_000) do
        machine.cycle!
        [machine.via1, machine.via2].flat_map { |via| check(via, machine.cycles) }
      end.flatten
    end
  end

  # Both timers running, timer 1 free-running with PB7 on, the shift
  # register clocking out off φ2 then timer 2, CA2 pulsing, and the
  # registers read now and then.
  def scripted
    @scripted ||= begin
      via = Badline::Chips::VIA.new(start: 0x1800)
      { 0x02 => 0xff, 0x00 => 0x5a, 0x0b => 0xd8, 0x0c => 0x0a, 0x0e => 0xc0, 0x04 => 0x34, 0x05 => 0x00,
        0x08 => 0x40, 0x09 => 0x00, 0x0a => 0xa5, 0x01 => 0x77 }.each { |reg, value| via.poke(0x1800 + reg, value) }
      Array.new(2_000) do |cycle|
        via.poke(0x180b, 0xc4) if cycle == 700
        via.poke(0x180a, 0x3c) if cycle == 710
        via.ca1 = cycle.odd? if (cycle % 50) < 2
        via.peek(0x1800 + (cycle % 16)) if (cycle % 29).zero?
        via.cycle!
        check(via, cycle)
      end.flatten
    end
  end
end

describe Badline::Chips::VIA::KeyedState do
  it "restores both of a VIC-20's VIAs on every cycle of its boot" do
    expect(VIAKeyedSamples.vic20.first(5)).to be_empty
  end

  it "restores a VIA counting, shifting and pulsing on every cycle" do
    expect(VIAKeyedSamples.scripted.first(5)).to be_empty
  end
end
