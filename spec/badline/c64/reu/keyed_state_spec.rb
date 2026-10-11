# frozen_string_literal: true

require "spec_helper"
require_relative "../../../support/keyed_oracle"
require_relative "../../../support/snapshot_scenarios"

# The REU's keyed fields against its positional save_state, which restores
# exactly: an REU saved through a stash, a swap, a verify and a
# fetch, with the end-of-block interrupt on, loaded into a fresh one, saves
# the same positional state, with the IRQ line worked out from the status.
module REUKeyedSamples
  extend KeyedOracle

  # Each transfer as the registers start it: C64 address, REU address and
  # bank, length, interrupt mask, then the command.
  TRANSFERS = [[0x0400, 0x0000, 0x00, 0x0100, 0xc0, 0x90], [0x0400, 0x0000, 0x00, 0x0080, 0xc0, 0x92],
               [0x0400, 0x0000, 0x00, 0x0100, 0xc0, 0x93], [0x2000, 0x0040, 0x01, 0x0100, 0xc0, 0x91]].freeze

  module_function

  def start(machine, transfer)
    c64, expansion, bank, length, mask, command = transfer
    { 0xdf02 => c64 & 0xff, 0xdf03 => c64 >> 8, 0xdf04 => expansion & 0xff, 0xdf05 => expansion >> 8,
      0xdf06 => bank, 0xdf07 => length & 0xff, 0xdf08 => length >> 8, 0xdf09 => mask,
      0xdf01 => command }.each { |address, value| machine.address_bus.poke(address, value) }
  end

  def samples
    @samples ||= begin
      machine = Badline::C64.new(reu: 512)
      machine.load_prg(SnapshotScenarios::DEMO_PRG)
      machine.cpu.program_counter = SnapshotScenarios::DEMO_START
      machine.run_cycles(10_000)
      TRANSFERS.flat_map do |transfer|
        start(machine, transfer)
        Array.new(700) do |cycle|
          machine.cycle!
          next [] unless (cycle % 7).zero? || cycle < 12

          fresh = Badline::C64.new(reu: 512).reu
          problems = keyed_round_trip(machine.reu, fresh).report.lines(verbose: true)
          problems << "positional state differs" unless positional(machine.reu) == positional(fresh)
          problems.map { |line| "cycle #{machine.cycles}: #{line}" }
        end.flatten
      end
    end
  end
end

describe Badline::C64::REU::KeyedState do
  it "restores the REU through each kind of transfer" do
    expect(REUKeyedSamples.samples.first(5)).to be_empty
  end
end
