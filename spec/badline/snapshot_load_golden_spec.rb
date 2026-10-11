# frozen_string_literal: true

require "spec_helper"
require "badline/c128"

# Snapshots saved by each release since the keyed modules, under
# spec/fixtures/snapshots/<version>/, never saved again: a C64, a VIC-20
# and a C128 typing PRINT 6*7, and a C64 loading the directory from a true
# 1541. Each loads into this badline and runs 100,000 cycles, after which
# its text screen reads as the screen saved beside it, which the release
# that saved it showed then.
describe Badline::Snapshot, ".load" do
  fixtures = File.expand_path("../fixtures/snapshots", __dir__)

  # The text screen in RAM, as bin/snapshot_check reads it.
  def screen(machine)
    ram = machine.ram
    base, columns, rows = machine.family == :vic20 ? [ram.peek(0x0288) << 8, 22, 23] : [0x0400, 40, 25]
    lines = Array.new(rows) do |row|
      Array.new(columns) { |column| character(ram.peek(base + (row * columns) + column)) }.join.rstrip
    end
    "#{lines.join("\n")}\n"
  end

  def character(code)
    code &= 0x7f
    return "@" if code.zero?
    return (code + 96).chr if code < 27

    code < 64 ? code.chr : " "
  end

  Dir[File.join(fixtures, "*", "*.vsf")].each do |path|
    name = path.delete_prefix("#{fixtures}/")

    it "loads the golden fixture #{name}, which runs on as it did" do
      machine = described_class.load(path) { nil }
      machine.run_cycles(100_000)
      expect(screen(machine)).to eq(File.read(path.sub(/\.vsf\z/, ".txt")))
    end
  end
end
