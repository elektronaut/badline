# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../test/support/snapshot_cartridges"

# Every mapper's keyed fields, saved again the same: bin/snapshot_check's
# matrix of mappers after register writes, reads, freezes and thaws, each
# saved, built again from its fields (Cartridge.from_fields), loaded and
# saved again.
module CartridgeKeyedSamples
  module_function

  def saved_fields(cartridge)
    out = Badline::Snapshot::Keyed::Writer.new
    cartridge.save_fields(out)
    out.to_s
  end

  def problems
    @problems ||= SnapshotCartridges.scenarios.flat_map do |name, cartridge|
      out = Badline::Snapshot::Keyed::Writer.new
      cartridge.save_fields(out)
      input = Badline::Snapshot::Keyed::Reader.parse(out.section("BL-CART"))
      copy = SnapshotCartridges.attach(Badline::C64::Cartridge.from_fields(input))
      copy.load_fields(input)
      lines = input.report.lines(verbose: true)
      lines << "saves other fields" unless saved_fields(copy) == saved_fields(cartridge)
      lines.map { |line| "#{name}: #{line}" }
    end
  end
end

describe Badline::C64::Cartridge::KeyedState do
  it "restores every mapper in the matrix" do
    expect(CartridgeKeyedSamples.problems.first(8)).to be_empty
  end
end
