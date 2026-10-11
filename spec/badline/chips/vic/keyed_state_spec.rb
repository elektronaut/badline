# frozen_string_literal: true

require "spec_helper"
require_relative "../../../support/keyed_oracle"
require_relative "../../../support/snapshot_scenarios"

# The VIC-II's keyed fields, saved again the same: a VIC saved on any
# column, loaded into a fresh machine's, saves the same fields, with the
# IRQ line, the sprites' BA columns and whether any sprite DMA runs worked
# out again. The g-access ring comes back oldest first, which the saved VIC
# is turned to as well before comparing: its slots are only ever read
# relative to the newest.
module VICKeyedSamples
  extend KeyedOracle

  module_function

  def rebase(vic)
    tick = vic.instance_variable_get(:@g_tick)
    order = Array.new(4) { |age| (tick + 1 + age) & 3 }
    %i[@g_kind @g_data @g_char @g_color].each do |name|
      ring = vic.instance_variable_get(name)
      ring.replace(order.map { |slot| ring[slot] })
    end
    vic.instance_variable_set(:@g_tick, 3)
    saved_fields(vic)
  end

  def demo_machine(**models)
    Badline::C64.new(**models).tap do |machine|
      machine.load_prg(SnapshotScenarios::DEMO_PRG)
      machine.cpu.program_counter = SnapshotScenarios::DEMO_START
    end
  end

  def check(machine, models)
    target = Badline::Chips::VIC.new(model: models.fetch(:vic_model, :mos6569))
    problems = keyed_round_trip(machine.vic, target).report.lines(verbose: true)
    problems << "saves other fields" unless rebase(machine.vic) == rebase(target)
    problems.map { |line| "cycle #{machine.cycles} (line #{machine.vic.rasterline}): #{line}" }
  end

  # The demo, sampled every 127th cycle through a frame, which reaches every
  # column of a line, with the sprites, the raster IRQ moving and the
  # background colour changing.
  def demo(**models)
    @demo ||= {}
    @demo[models] ||= begin
      machine = demo_machine(**models)
      machine.run_cycles(20_000)
      problems = []
      20_000.times do |cycle|
        machine.cycle!
        problems.concat(check(machine, models)) if (cycle % 127).zero?
      end
      problems
    end
  end

  # A C128's VIC-IIe through its boot, its display line and TEST wrap
  # included.
  def iie
    @iie ||= begin
      machine = Badline::C128.new
      problems = []
      30_000.times do |cycle|
        machine.cycle!
        problems.concat(check(machine, { vic_model: machine.vic.model })) if (cycle % 127).zero?
      end
      problems
    end
  end
end

describe Badline::Chips::VIC::KeyedState do
  it "restores the 6569 on any column of the demo" do
    expect(VICKeyedSamples.demo.first(5)).to be_empty
  end

  it "restores the 8565 on any column of the demo" do
    expect(VICKeyedSamples.demo(vic_model: :mos8565, cia_model: :mos6526a).first(5)).to be_empty
  end

  it "restores a C128's VIC-IIe" do
    expect(VICKeyedSamples.iie.first(5)).to be_empty
  end

  describe "a snapshot from another renderer" do
    let(:machine) { VICKeyedSamples.demo_machine.tap { |c64| c64.run_cycles(30_017) } }
    let(:target) { Badline::Chips::VIC.new }

    let(:input) do
      out = Badline::Snapshot::Keyed::Writer.new
      machine.vic.save_fields(out)
      out.int("line.layout", 99)
      Badline::Snapshot::Keyed::Reader.parse(out.section("BL-VIC"))
    end

    before do
      target.load_fields(input)
      target.restored!
    end

    it "reports the line restarted" do
      expect(input.report.adjusted).to include("line in progress from another renderer, restarted")
    end

    it "keeps the beam and the registers" do
      expect([target.rasterline, target.register_file]).to eq([machine.vic.rasterline, machine.vic.register_file])
    end
  end
end
