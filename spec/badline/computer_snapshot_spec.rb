# frozen_string_literal: true

require "spec_helper"
require_relative "../support/snapshot_scenarios"

describe Badline::Computer, "#snapshot" do
  include SnapshotScenarios

  let(:state) { SnapshotScenarios.demo_state }

  def checkpoints(first, second, cycles, every: 2_500)
    Array.new(cycles / every) do
      run(first, every)
      run(second, every)
      [Badline::Checkpoint.take(first), Badline::Checkpoint.take(second)]
    end
  end

  describe "a machine restored into a new one" do
    let(:original) { run(demo_machine, SnapshotScenarios::DEMO_CYCLES) }

    it "holds the state of a machine run the whole way" do
      expect(state_differences(original, saved_demo)).to be_empty
    end

    it "runs on as that machine does" do
      checkpoints(original, saved_demo, 10_000).each { |ours, theirs| expect(theirs).to eq(ours) }
    end
  end

  it "leaves the machine it is taken of alone" do
    machine = saved_demo
    machine.snapshot
    expect(machine.snapshot).to eq(state)
  end

  describe "#restore" do
    # A running machine, at another odd cycle, with the SID recording.
    let(:target) { run(described_class.new, 5_003).tap { |machine| machine.sid.record(rate: 44_100) } }

    it "takes a running machine back to the state" do
      target.restore(state)
      expect(state_differences(saved_demo, target)).to be_empty
    end

    it "keeps the machine's chips, and what is wired to them" do
      sid = target.sid
      target.restore(state)
      expect(target.sid).to equal(sid)
    end

    it "leaves the host's recording of the SID running" do
      target.restore(state)
      run(target, 1_000)
      expect(target.sid.drain_samples).not_to be_empty
    end

    it "fails on the state of a machine built another way" do
      expect { described_class.new(vic_model: :mos8565).restore(state) }
        .to raise_error(Badline::Snapshot::FormatError, /mos6569, mos6526, mos6581, pal/)
    end

    it "fails on a state that goes on past the machine" do
      longer = Badline::Snapshot::State.new(state.values + [0], state.strings)
      expect { target.restore(longer) }.to raise_error(Badline::Snapshot::FormatError, /goes on past/)
    end
  end

  describe ".setup" do
    it "builds the machine the state was taken of" do
      machine = described_class.new(vic_model: :mos8565, cia_model: :mos6526a, sid_model: :mos8580,
                                    ram_expansion: :plus256k)
      built = described_class.setup(machine.snapshot).build
      expect([built.vic.model, built.cia1.model, built.sid.model, built.address_bus.ram_expansion.type])
        .to eq(%i[mos8565 mos6526a mos8580 plus256k])
    end
  end

  describe "on_init handlers" do
    let(:booting) { described_class.new.tap { |machine| machine.on_init { nil } } }

    it "counts those a new machine doesn't have" do
      machine = described_class.new.restore(booting.snapshot)
      expect(machine.init_handlers_lost).to eq(1)
    end

    it "counts none when the machine has its own" do
      booting.restore(booting.snapshot)
      expect(booting.init_handlers_lost).to eq(0)
    end

    it "counts none once the saved machine has booted" do
      booting.resume_at(described_class::INIT_THRESHOLD + 1)
      expect(described_class.new.restore(booting.snapshot).init_handlers_lost).to eq(0)
    end
  end

  describe "with a RAM expansion" do
    let(:machine) do
      described_class.new(ram_expansion: :plus256k).tap do |computer|
        computer.address_bus.poke(0xd100, 0b0100_0001)
        computer.address_bus.poke(0x2000, 0x42)
      end
    end

    it "keeps the banks and the register" do
      restored = described_class.setup(machine.snapshot).build.restore(machine.snapshot)
      expect(state_differences(machine, restored)).to be_empty
    end
  end
end
