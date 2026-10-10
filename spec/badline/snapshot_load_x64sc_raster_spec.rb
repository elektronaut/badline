# frozen_string_literal: true

require "spec_helper"
require_relative "../support/snapshot_scenarios"

# The fixtures: x64sc 3.10 on macOS, run with -model as named, no drive
# and badline's own ROMs, booted, then given a program at $C000 through the
# remote monitor and saved with `dump` a few instructions into it, and
# gzipped. The program samples $D012 and $D011, 23 cycles apart, into
# $C100 and $C200, 256 times, and stops in a JMP to itself. Each .samples
# file holds the 512 bytes x64sc left there, read with the monitor once
# it reached that JMP.
#
# x64sc310-reu ran -model c64 with a 512K REU, and its program stashes
# $0400 bytes from $0400 to the REU first, then samples $D012 alone into
# $C100. It was saved once the stash had ended.
describe Badline::Snapshot, ".load" do
  include SnapshotScenarios

  def fixture(name) = File.expand_path("../fixtures/#{name}", __dir__)

  def samples(name) = File.binread(fixture(name)).bytes

  def run_to(machine, address)
    machine.cycle! until machine.cpu.boundary? && machine.cpu.program_counter == address
    Array.new(512) { |offset| machine.ram.peek(0xc100 + offset) }
  end

  %w[c64 ntsc oldntsc drean].each do |name|
    context "with x64sc's snapshot of a #{name} sampling the raster" do
      let(:machine) { described_class.load(fixture("x64sc310-raster-#{name}.vsf.gz")) { nil } }

      it "builds the #{name}" do
        expect(Badline::Model.of(Badline::Snapshot::C64Setup.of(machine.address_bus))).to eq(Badline::Model.named(name))
      end

      it "reads the raster as x64sc did, cycle for cycle" do
        expect(run_to(machine, 0xc012)).to eq(samples("x64sc310-raster-#{name}.samples"))
      end
    end
  end

  context "with x64sc's snapshot of a C64 with an REU" do
    let(:machine) { described_class.load(fixture("x64sc310-reu.vsf.gz")) { nil } }

    it "builds a 512K REU holding what was stashed" do
      expect([machine.reu.size_kb, machine.reu.ram_contents.byteslice(0, 0x400).bytes])
        .to eq([512, machine.ram.read(0x0400, 0x400)])
    end

    it "restores the REU's registers as the stash left them" do
      expect(machine.reu.register_file.first(11)).to eq([0x50, 0x10, 0x00, 0x08, 0x00, 0x04, 0xf8, 0x01, 0x00, 0x1f,
                                                         0x3f])
    end

    it "reads the raster as x64sc did, cycle for cycle" do
      expect(run_to(machine, 0xc02e)).to eq(samples("x64sc310-reu.samples"))
    end
  end
end
