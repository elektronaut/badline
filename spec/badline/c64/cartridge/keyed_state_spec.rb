# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../test/support/snapshot_cartridges"

# Every mapper's keyed fields against its positional setup and state, which
# restore exactly: bin/snapshot_check's matrix of mappers after register
# writes, reads, freezes and thaws, each saved, built again from its
# fields (Cartridge.from_fields) and loaded.
module CartridgeKeyedSamples
  module_function

  def positional(cartridge)
    out = Badline::Snapshot::StateWriter.new
    cartridge.save_setup(out)
    cartridge.save_state(out)
    out.state
  end

  def problems
    @problems ||= SnapshotCartridges.scenarios.flat_map do |name, cartridge|
      out = Badline::Snapshot::Keyed::Writer.new
      cartridge.save_fields(out)
      input = Badline::Snapshot::Keyed::Reader.parse(out.section("BL-CART"))
      copy = SnapshotCartridges.attach(Badline::C64::Cartridge.from_fields(input))
      copy.load_fields(input)
      lines = input.report.lines(verbose: true)
      lines << "positional state differs" unless positional(copy) == positional(cartridge)
      lines.map { |line| "#{name}: #{line}" }
    end
  end
end

describe Badline::C64::Cartridge::KeyedState do
  it "restores every mapper in the matrix" do
    expect(CartridgeKeyedSamples.problems.first(8)).to be_empty
  end
end
