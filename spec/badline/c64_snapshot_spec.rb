# frozen_string_literal: true

require "spec_helper"
require_relative "../support/snapshot_scenarios"
require_relative "../support/taken_once"

describe Badline::C64, "#snapshot" do
  include SnapshotScenarios

  let(:image) { SnapshotScenarios.demo_image }

  def checkpoints(first, second, cycles, every: 2_500)
    Array.new(cycles / every) do
      run(first, every)
      run(second, every)
      [Badline::Support::Checkpoint.take(first), Badline::Support::Checkpoint.take(second)]
    end
  end

  # A machine with one module of `image` changed by the block.
  def with_module(image, name)
    sections = image.sections.map { |section| section.name == name ? yield(section) : section }
    Badline::Snapshot::Image.new(Badline::Snapshot::Container.new(sections))
  end

  describe "a machine restored into a new one" do
    let(:original) { run(demo_machine, SnapshotScenarios::DEMO_CYCLES).tap(&:settle_for_snapshot!) }

    it "saves what a machine run the whole way saves" do
      expect(saved_demo.snapshot).to eq(original.snapshot)
    end

    it "runs on as that machine does" do
      checkpoints(original, saved_demo, 10_000).each { |ours, theirs| expect(theirs).to eq(ours) }
    end
  end

  it "runs the machine on to an instruction boundary" do
    machine = run(demo_machine, SnapshotScenarios::DEMO_CYCLES)
    machine.snapshot
    expect([machine.cpu.boundary?, machine.cycles >= SnapshotScenarios::DEMO_CYCLES]).to eq([true, true])
  end

  it "leaves a machine that has just saved alone" do
    machine = saved_demo
    expect { machine.snapshot }.not_to(change(machine, :cycles))
  end

  describe "#restore" do
    # A running machine, at another odd cycle, with the SID recording.
    let(:target) { run(described_class.new, 5_003).tap { |machine| machine.sid.record(rate: 44_100) } }

    it "takes a running machine back to the snapshot" do
      target.restore(image)
      expect(target.snapshot).to eq(image)
    end

    it "keeps the machine's chips, and what is wired to them" do
      sid = target.sid
      target.restore(image)
      expect(target.sid).to equal(sid)
    end

    it "leaves the host's recording of the SID running" do
      target.restore(image)
      run(target, 1_000)
      expect(target.sid.drain_samples).not_to be_empty
    end

    it "fails on the snapshot of a machine built another way" do
      expect { described_class.new(vic_model: :mos8565).restore(image) }
        .to raise_error(Badline::Snapshot::FormatError, /mos6569, mos6526, mos6581, pal/)
    end

    it "names the model of each machine when it fails" do
      c64c = Badline::Model::C64C
      machine = described_class.new(vic_model: c64c.vic_model, cia_model: c64c.cia_model, sid_model: c64c.sid_model)
      expect { machine.restore(image) }.to raise_error(Badline::Snapshot::FormatError, /with c64, .* not c64c, /)
    end

    it "fails on another family's snapshot" do
      expect { target.restore(Badline::Vic20.new.snapshot) }
        .to raise_error(Badline::Snapshot::FormatError, /of a VIC-20, not a C64/)
    end
  end

  describe "#restore of a damaged snapshot" do
    # The VIC's module cut short, so it won't inflate.
    let(:damaged) { with_module(image, "BL-VIC") { |section| section.with(data: section.data.byteslice(0, 40)) } }
    let(:target) do
      TakenOnce.fetch([:c64_running_image, 500_001]) { run(described_class.new, 500_001).snapshot }.load
    end

    def attempt(machine, image)
      machine.restore(image)
    rescue Badline::Snapshot::FormatError
      nil
    end

    it "fails naming the module" do
      expect { target.restore(damaged) }.to raise_error(Badline::Snapshot::FormatError, /BL-VIC is damaged/)
    end

    it "leaves the machine as it was" do
      saved = target.snapshot
      attempt(target, damaged)
      expect(target.snapshot).to eq(saved)
    end
  end

  describe "a module written by a later badline's encoding" do
    let(:newer) { with_module(image, "BL-SID") { |section| section.with(major: 2) } }

    it "fails naming the module" do
      expect { newer.load }.to raise_error(Badline::Snapshot::FormatError, /BL-SID 2.0 was written by a newer/)
    end
  end

  describe "a snapshot with fields and modules from a later badline" do
    let(:later) do
      extra = Badline::Snapshot::Keyed.section("BL-LATER") { |out| out.int("x", 1) }
      cpu = with_module(image, "BL-CPU") do |section|
        records = Badline::Snapshot::Keyed::Writer.new.int("later.latch", 7).to_s
        section.with(data: Zlib.deflate(Zlib.inflate(section.data) + records))
      end
      Badline::Snapshot::Image.new(Badline::Snapshot::Container.new(cpu.sections + [extra]))
    end
    let(:lines) { [] }
    let(:loaded) { later.load { |line| lines << line } }

    it "skips what it doesn't know" do
      expect(loaded.snapshot).to eq(image)
    end

    it "reports the module it left out, and the field only in the report" do
      report = later.restore(described_class.new) { nil }
      expect([report.ignored, report.unknown]).to eq([["BL-LATER: badline doesn't read this module, left out"],
                                                      { "BL-CPU" => ["later.latch"] }])
    end
  end

  describe "a snapshot missing a module" do
    let(:missing) do
      Badline::Snapshot::Image.new(Badline::Snapshot::Container.new(image.sections.reject do |section|
        section.name == "BL-SID"
      end))
    end

    it "reports it, leaving the chip at power-on" do
      expect(missing.restore(described_class.new) { nil }.missing).to eq(["BL-SID"])
    end
  end

  describe "setup" do
    def rebuilt(machine) = machine.snapshot.load

    it "builds the machine the snapshot was taken of" do
      machine = described_class.new(vic_model: :mos8565, cia_model: :mos6526a, sid_model: :mos8580,
                                    ram_expansion: :plus256k)
      built = rebuilt(machine)
      expect([built.vic.model, built.cia1.model, built.sid.model, built.address_bus.ram_expansion.type])
        .to eq(%i[mos8565 mos6526a mos8580 plus256k])
    end

    it "builds a machine of the first NTSC C64s" do
      expect(rebuilt(described_class.new(region: Badline::Region::NTSC_OLD)).region).to eq(Badline::Region::NTSC_OLD)
    end

    it "builds an SX-64 with its KERNAL and without a datasette" do
      built = rebuilt(described_class.new(kernal: :sx64, datasette: false))
      expect([built.address_bus.kernal, built.datasette.connected?]).to eq([:sx64, false])
    end

    it "names the SX-64 when it fails" do
      sx64 = described_class.new(kernal: :sx64, datasette: false)
      expect { sx64.restore(image) }.to raise_error(Badline::Snapshot::FormatError, /not sx64, /)
    end

    it "builds the PET 64's board" do
      expect(rebuilt(described_class.new(board: :pet64)).address_bus.board).to eq(:pet64)
    end

    it "names the PET 64's board when it fails" do
      expect { described_class.new(board: :pet64).restore(image) }
        .to raise_error(Badline::Snapshot::FormatError, /not .*the pet64 board/)
    end

    it "builds the C64GS's board" do
      expect(rebuilt(described_class.new(board: :gs)).keyboard.connected?).to be(false)
    end

    it "builds the MAX Machine's board" do
      expect(rebuilt(described_class.new(board: :max)).address_bus.board).to eq(:max)
    end

    it "builds a Drean machine" do
      expect(rebuilt(described_class.new(region: Badline::Region::DREAN)).region).to eq(Badline::Region::DREAN)
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

  describe "typing" do
    # Saved while autostart's RUN is still on its way into the keyboard
    # buffer, past the boot.
    let(:typing) do
      described_class.new.tap do |machine|
        machine.type_text("print 6*7\r" * 3)
        run(machine, 2_500_200)
      end
    end

    it "types the rest of the text after a restore" do
      restored = typing.snapshot.load
      expect(run(restored, 300_000).snapshot).to eq(run(typing, 300_000).snapshot)
    end
  end

  describe "typing before the boot" do
    let(:booting) { described_class.new.tap { |machine| machine.type_text("run\r") } }

    it "saves the text with the machine" do
      expect(booting.snapshot.load.snapshot).to eq(booting.snapshot)
    end

    it "types the text once the restored machine has booted" do
      restored = booting.snapshot.load
      restored.resume_at(described_class::INIT_THRESHOLD)
      restored.ram.poke(0xc6, 0)
      restored.cycle!
      expect(restored.ram.read(0x0277, 4)).to eq([0x52, 0x55, 0x4e, 0x0d])
    end
  end

  describe "with an REU" do
    # A 16M REU part way through a swap, with its interrupt raised by the
    # stash before it. Saving runs the swap to its end.
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

    it "restores the REU's registers, RAM and IRQ line" do
      image = machine.snapshot
      expect(image.load.snapshot).to eq(image)
    end

    it "runs on as the saved machine does" do
      restored = machine.snapshot.load
      run(machine, 5_000)
      run(restored, 5_000)
      expect(Badline::Support::Checkpoint.take(restored)).to eq(Badline::Support::Checkpoint.take(machine))
    end

    it "builds the machine with an REU of the same size" do
      expect(machine.snapshot.load.reu.size_kb).to eq(16_384)
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
      image = machine.snapshot
      expect(described_class.new(ram_expansion: :plus256k).restore(image).snapshot).to eq(image)
    end
  end
end
