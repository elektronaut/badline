# frozen_string_literal: true

require "spec_helper"
require_relative "../support/snapshot_scenarios"
require_relative "../support/taken_once"

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

  # Layout 3 wrote the setup without the KERNAL, the datasette and the
  # board, the three values after the REU's size.
  describe "a state in layout 3" do
    let(:original) { run(demo_machine, SnapshotScenarios::DEMO_CYCLES) }
    let(:restored) do
      values = original.snapshot.values.dup
      values[0] = 3
      values.slice!(7, 3)
      described_class.restored(Badline::Snapshot::State.new(values, original.snapshot.strings))
    end

    it "builds a C64 with its KERNAL and a datasette" do
      expect([restored.address_bus.kernal, restored.datasette.connected?]).to eq([:c64, true])
    end

    it "runs on as the saved machine does" do
      checkpoints(original, restored, 10_000).each { |ours, theirs| expect(theirs).to eq(ours) }
    end
  end

  # Layout 5 wrote the setup without the board, the value after the
  # datasette.
  describe "a state in layout 5" do
    let(:original) { run(demo_machine, SnapshotScenarios::DEMO_CYCLES) }
    let(:restored) do
      values = original.snapshot.values.dup
      values[0] = 5
      values.delete_at(9)
      described_class.restored(Badline::Snapshot::State.new(values, original.snapshot.strings))
    end

    it "builds a C64's board" do
      expect(restored.address_bus.board).to eq(:c64)
    end

    it "runs on as the saved machine does" do
      checkpoints(original, restored, 10_000).each { |ours, theirs| expect(theirs).to eq(ours) }
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

    it "names the model of each machine when it fails" do
      c64c = Badline::Model::C64C
      machine = described_class.new(vic_model: c64c.vic_model, cia_model: c64c.cia_model, sid_model: c64c.sid_model)
      expect { machine.restore(state) }.to raise_error(Badline::Snapshot::FormatError, /with c64, .* not c64c, /)
    end

    it "fails on a state that goes on past the machine" do
      longer = Badline::Snapshot::State.new(state.values + [0], state.strings)
      expect { target.restore(longer) }.to raise_error(Badline::Snapshot::FormatError, /goes on past/)
    end

    it "fails on a state written in another layout" do
      values = state.values.dup
      values[0] = Badline::Snapshot::State::SCHEMA + 1
      expect { target.restore(Badline::Snapshot::State.new(values, state.strings)) }
        .to raise_error(Badline::Snapshot::FormatError, /layout #{Badline::Snapshot::State::SCHEMA + 1}/o)
    end
  end

  describe "#restore of a damaged state" do
    # A value three quarters of the way in taken out, so everything after
    # it reads one place early.
    let(:damaged) do
      values = state.values.dup
      values.delete_at(values.length * 3 / 4)
      Badline::Snapshot::State.new(values, state.strings)
    end
    let(:target) do
      described_class.restored(TakenOnce.fetch([:c64_running, 500_001]) { run(described_class.new, 500_001).snapshot })
    end

    def attempt(machine, state)
      machine.restore(state)
    rescue Badline::Snapshot::FormatError
      nil
    end

    it "fails" do
      expect { target.restore(damaged) }.to raise_error(Badline::Snapshot::FormatError)
    end

    it "leaves the machine as it was" do
      saved = target.snapshot
      attempt(target, damaged)
      expect(target.snapshot).to eq(saved)
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

    it "builds a machine of the first NTSC C64s" do
      machine = described_class.new(region: Badline::Region::NTSC_OLD)
      expect(described_class.setup(machine.snapshot).build.region).to eq(Badline::Region::NTSC_OLD)
    end

    it "builds an SX-64 with its KERNAL and without a datasette" do
      machine = described_class.new(kernal: :sx64, datasette: false)
      built = described_class.setup(machine.snapshot).build
      expect([built.address_bus.kernal, built.datasette.connected?]).to eq([:sx64, false])
    end

    it "names the SX-64 when it fails" do
      sx64 = described_class.new(kernal: :sx64, datasette: false)
      expect { sx64.restore(state) }.to raise_error(Badline::Snapshot::FormatError, /not sx64, /)
    end

    it "builds the PET 64's board" do
      machine = described_class.new(board: :pet64)
      expect(described_class.setup(machine.snapshot).build.address_bus.board).to eq(:pet64)
    end

    it "names the PET 64's board when it fails" do
      expect { described_class.new(board: :pet64).restore(state) }
        .to raise_error(Badline::Snapshot::FormatError, /not .*the pet64 board/)
    end

    it "builds the C64GS's board" do
      machine = described_class.new(board: :gs)
      expect(described_class.setup(machine.snapshot).build.keyboard.connected?).to be(false)
    end

    it "builds the MAX Machine's board" do
      machine = described_class.new(board: :max)
      expect(described_class.setup(machine.snapshot).build.address_bus.board).to eq(:max)
    end

    it "builds a Drean machine" do
      machine = described_class.new(region: Badline::Region::DREAN)
      expect(described_class.setup(machine.snapshot).build.region).to eq(Badline::Region::DREAN)
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
      booting.resume_at(booting.init_threshold + 1)
      expect(described_class.new.restore(booting.snapshot).init_handlers_lost).to eq(0)
    end
  end

  describe "with an REU" do
    # A 16M REU part way through a swap, with its interrupt raised by the
    # stash before it.
    let(:machine) do
      described_class.new(reu: 16_384).tap do |computer|
        bus = computer.address_bus
        { 0xdf02 => 0x00, 0xdf03 => 0x10, 0xdf04 => 0x34, 0xdf05 => 0x12, 0xdf06 => 0x85, 0xdf07 => 0x00,
          0xdf08 => 0x02, 0xdf09 => 0xe0, 0xdf01 => 0x90 }.each { |addr, value| bus.poke(addr, value) }
        run(computer, 7_003)
        [[0xdf08, 0x02], [0xdf01, 0x92]].each { |addr, value| bus.poke(addr, value) }
        run(computer, 41)
      end
    end

    it "restores the REU's registers, transfer, RAM and IRQ line" do
      restored = described_class.restored(machine.snapshot)
      expect(state_differences(machine, restored, host: { "Badline::REU::RAM" => %i[@power_on] })).to be_empty
    end

    it "runs on as the saved machine does" do
      restored = described_class.restored(machine.snapshot)
      run(machine, 5_000)
      run(restored, 5_000)
      expect(Badline::Checkpoint.take(restored)).to eq(Badline::Checkpoint.take(machine))
    end

    it "builds the machine with an REU of the same size" do
      expect(described_class.setup(machine.snapshot).build.reu.size_kb).to eq(16_384)
    end

    it "fails to restore into a machine without one" do
      expect { described_class.new.restore(machine.snapshot) }
        .to raise_error(Badline::Snapshot::FormatError, /a 16384K REU/)
    end
  end

  describe "with a RAM expansion" do
    let(:machine) do
      described_class.new(ram_expansion: :plus256k).tap do |computer|
        computer.address_bus.poke(0xd100, 0b0100_1001)
        computer.address_bus.poke(0x2000, 0x42)
      end
    end

    it "keeps the banks and the register" do
      restored = described_class.setup(machine.snapshot).build.restore(machine.snapshot)
      expect(state_differences(machine, restored)).to be_empty
    end
  end
end
