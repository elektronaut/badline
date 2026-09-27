# frozen_string_literal: true

require "spec_helper"
require_relative "../support/snapshot_scenarios"

# The fixture: x64sc 3.7.1 run with -model c64, booted, PRINT 6*7 typed
# through the keyboard buffer from the remote monitor, then saved with the
# monitor's `dump` and gzipped. It carries no ROM module.
describe Badline::Snapshot, ".load" do
  include SnapshotScenarios

  context "with a snapshot x64sc wrote" do
    let(:path) { File.expand_path("../fixtures/x64sc-print42.vsf.gz", __dir__) }
    let(:lines) { [] }
    let(:machine) { described_class.load(path) { |line| lines << line } }

    def screen(machine)
      Array.new(25) do |row|
        codes = Array.new(40) { |column| machine.ram.peek(0x0400 + (row * 40) + column) }
        codes.pack("C*").tr("\x01-\x1a", "A-Z").rstrip
      end.reject(&:empty?)
    end

    it "builds the breadbin C64 it was saved from" do
      expect([machine.vic.model, machine.cia1.model, machine.sid.model]).to eq(%i[mos6569 mos6526 mos6581])
    end

    it "restores the CPU where x64sc stopped it" do
      expect([machine.cpu.program_counter, machine.cpu.stack_pointer, machine.cycles]).to eq([0xe5cf, 0xf3, 22_545_433])
    end

    it "restores the screen" do
      expect(screen(machine)).to include("PRINT 6*7", " 42")
    end

    it "reports the modules it leaves out" do
      machine
      expect(lines.map { |line| line.split.first })
        .to eq(%w[C64CART DRIVE8 DRIVE9 DRIVE10 DRIVE11 FSDRIVE GLUE C64MEMHACKS TAPEPORT DATASETTE KEYBOARD
                  JOYPORT0 JOYSTICK0 JOYPORT1 JOYSTICK1 USERPORT])
    end

    it "runs BASIC on" do
      machine.type_text("print 7*8\r")
      run(machine, 50_000)
      expect(screen(machine)).to include("PRINT 7*8", " 56")
    end
  end
end
