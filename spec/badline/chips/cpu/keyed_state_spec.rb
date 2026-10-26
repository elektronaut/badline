# frozen_string_literal: true

require "spec_helper"
require_relative "../../../support/keyed_oracle"
require_relative "../../../support/snapshot_scenarios"

# The CPU's keyed fields, saved again the same: a CPU saved on any cycle,
# loaded into a fresh one, saves the same fields, with the IRQ line, a
# stall too long ago to matter and the working registers between
# instructions set on the saved one as a keyed load leaves them.
module CPUKeyedSamples
  extend KeyedOracle

  CHIP = Badline::Chips::CPU

  module_function

  # The working registers no step reads once an instruction ends, as the
  # keyed load leaves them at a boundary.
  LATCHES = { :@boundary_crossed => false, :@branch_taken => false, :@brk => false, :@interrupt => nil,
              :@address => nil, :@dummy_address => nil, :@value => nil, :@rmw_result => nil,
              :@pointer => nil }.freeze

  # The saved fields, with the IRQ line the machine drives before every
  # cycle, a stall too long ago for any step to look back at, and the
  # registers no step reads again, set as a keyed load leaves them.
  def comparable(cpu)
    plan = cpu.instance_variable_get(:@plan)
    stalled_at = cpu.instance_variable_get(:@stalled_at)
    fields = { :@irq => false }
    fields[:@stalled_at] = nil unless stalled_at && (cpu.cycles - stalled_at).between?(0, 1)
    fields.merge!(:@operation => nil, :@optional_dummy => false) unless instruction?(plan)
    fields.merge!(LATCHES) if cpu.boundary? || cpu.jammed?
    saved_fields(with_fields(cpu, fields))
  end

  def instruction?(plan)
    [CHIP::FETCH_PLAN, CHIP::INTERRUPT_PLAN, CHIP::JAMMED_PLAN, CHIP::RESET_PLAN].none? { |other| plan.equal?(other) }
  end

  # Where the CPU is, for the coverage the samples reach.
  def position(cpu)
    plan = cpu.instance_variable_get(:@plan)
    return :boundary if cpu.boundary?
    return :jammed if cpu.jammed?
    return :interrupt if plan.equal?(CHIP::INTERRUPT_PLAN)
    return :reset if plan.equal?(CHIP::RESET_PLAN)

    micro = CHIP::MICROCODE.find { |each| each.plan.equal?(plan) }
    micro.skips_dummy?(cpu.instance_variable_get(:@index) - 1, cpu.boundary_crossed) ? :skipped_dummy : :instruction
  end

  # Round trips `cpu` into `fresh` and returns what differs.
  def check(cpu, fresh)
    input = keyed_round_trip(cpu, fresh)
    problems = input.report.lines(verbose: true)
    problems << "saves other fields" unless comparable(cpu) == comparable(fresh)
    problems.map { |line| "cycle #{cpu.cycles} (#{position(cpu)}): #{line}" }
  end

  # Samples a CPU after every one of `cycles` cycles of `machine`, and
  # returns the problems and the positions seen.
  def sample(machine, cycles, cpu: -> { machine.cpu }, fresh: -> { CHIP.new(machine.address_bus) })
    problems = []
    seen = Hash.new(0)
    stalls = 0
    cycles.times do
      machine.cycle!
      seen[position(cpu.call)] += 1
      stalls += 1 unless cpu.call.send(:stalled_ago).nil?
      problems.concat(check(cpu.call, fresh.call))
    end
    { problems:, seen:, stalls: }
  end

  def demo
    @demo ||= begin
      machine = Badline::C64.new
      machine.load_prg(SnapshotScenarios::DEMO_PRG)
      machine.cpu.program_counter = SnapshotScenarios::DEMO_START
      sample(machine, 20_000)
    end
  end

  def drive
    @drive ||= begin
      machine = Badline::C64.new
      drive = machine.plug_true_drive
      sample(machine, 20_000, cpu: -> { drive.cpu },
                              fresh: -> { Badline::Drives::Model1541::CPU.new(drive.cpu.memory) })
    end
  end

  def jam
    @jam ||= begin
      memory = Badline::Memory.new.tap { |m| m.write(0xc000, [0xea, 0x02]) }
      cpu = CHIP.new(memory).tap { |each| each.program_counter = 0xc000 }
      problems = []
      12.times do
        cpu.cycle!
        problems.concat(check(cpu, CHIP.new(memory)))
      end
      { problems:, jammed: cpu.jammed? }
    end
  end
end

describe Badline::Chips::CPU::KeyedState do
  describe "the C64's CPU on every cycle of the demo" do
    it "saves the same fields" do
      expect(CPUKeyedSamples.demo[:problems].first(5)).to be_empty
    end

    it "is caught at boundaries, inside instructions, past a skipped dummy read and in interrupt sequences" do
      expect(CPUKeyedSamples.demo[:seen].keys).to include(:boundary, :instruction, :skipped_dummy, :interrupt)
    end

    it "is caught just after a stall" do
      expect(CPUKeyedSamples.demo[:stalls]).to be_positive
    end
  end

  describe "a 1541's CPU on every cycle from power-on" do
    it "saves the same fields" do
      expect(CPUKeyedSamples.drive[:problems].first(5)).to be_empty
    end

    it "is caught inside instructions" do
      expect(CPUKeyedSamples.drive[:seen][:instruction]).to be_positive
    end
  end

  describe "a CPU through a JAM opcode" do
    it "saves the same fields on every cycle" do
      expect(CPUKeyedSamples.jam[:problems]).to be_empty
    end

    it "ends jammed" do
      expect(CPUKeyedSamples.jam[:jammed]).to be(true)
    end
  end

  describe "Microcode#index_at" do
    let(:lda_absolute_x) { CPUKeyedSamples::CHIP::MICROCODE[0xbd] }

    it "steps past the dummy read an indexed read skips" do
      expect([1, 2, 3].map { |cycles| lda_absolute_x.index_at(cycles, false) }).to eq([1, 2, 4])
    end

    it "keeps the dummy read once the index add crosses a page" do
      expect([1, 2, 3].map { |cycles| lda_absolute_x.index_at(cycles, true) }).to eq([1, 2, 3])
    end

    it "counts the cycles back from the step" do
      expect([1, 2, 4].map { |index| lda_absolute_x.t_at(index, false) }).to eq([1, 2, 3])
    end
  end
end
