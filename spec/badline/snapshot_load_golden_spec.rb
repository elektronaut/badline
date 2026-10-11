# frozen_string_literal: true

require "spec_helper"
require "badline/c128"
require_relative "../../test/support/snapshot_golden"

# Snapshots saved by each release since the keyed modules, under
# spec/fixtures/snapshots/<version>/ by rake snapshot:golden, never saved
# again: a C64, a VIC-20 and a C128 typing PRINT 6*7, a C64 loading the
# directory from a true 1541, and a C64 running the Super Games cartridge
# test. Each loads into this badline and runs 100,000 cycles, after which
# its text screen reads as the screen saved beside it, which the release
# that saved it showed then.
describe Badline::Snapshot, ".load" do
  fixtures = File.expand_path("../fixtures/snapshots", __dir__)

  Dir[File.join(fixtures, "*", "*.vsf")].each do |path|
    name = path.delete_prefix("#{fixtures}/")

    it "loads the golden fixture #{name}, which runs on as it did" do
      machine = described_class.load(path) { nil }
      machine.run_cycles(100_000)
      expect(SnapshotGolden.screen(machine)).to eq(File.read(path.sub(/\.vsf\z/, ".txt")))
    end
  end

  # 0.14.0 named the bank each window showed, where later releases save the
  # mapper's register. Its Super Games showed bank 1 at ROML, $00 at $8000
  # where bank 0 has its start vector, and $02 at $9000 where banks 2 and 3
  # have $00.
  it "loads 0.14.0's cartridge with the bank it named at ROML" do
    machine = described_class.load(File.expand_path("../fixtures/snapshots/0.14.0/c64-cartridge.vsf", __dir__)) { nil }
    expect([machine.peek(0x8000), machine.peek(0x9000)]).to eq([0x00, 0x02])
  end
end
