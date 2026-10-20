# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require_relative "../support/taken_once"

describe Badline::KIM1 do
  describe "snapshots" do
    let(:path) { File.join(Dir.mktmpdir, "kim1.vsf") }

    # A KIM-1 on a teletype part way through printing its prompt, with
    # 0200 and a space still to type, restored from a snapshot taken once.
    def saved
      TakenOnce.fetch(:kim1_teletype_image) do
        described_class.new(tty: true, ram: :"5k").tap do |machine|
          machine.type_text("0200 ")
          machine.run_cycles(6_001)
        end.snapshot
      end.load
    end

    it "restores a machine that runs on as the saved one" do
      machine = saved
      restored = machine.snapshot.load
      [machine, restored].each { |each_machine| each_machine.run_cycles(20_000) }
      expect(restored.snapshot).to eq(machine.snapshot)
    end

    it "keeps what the teletype has printed and has still to type" do
      machine = saved
      machine.run_cycles(60_000)
      expect(machine.teletype.output.delete("\x00")).to include("KIM\r\n0000 00 0200 ")
    end

    it "saves to a .vsf whose machine is KIM1, with badline's modules alone" do
      saved.save_snapshot(path)
      snapshot = Badline::Snapshot.read(path)
      expect([snapshot.container.machine, snapshot.sections.map(&:name)])
        .to eq(["KIM1", %w[BL-MACHINE BL-CPU BL-RAM BL-U2 BL-U3 BL-PANEL BL-DECK BL-TTY BL-SOUND]])
    end

    it "builds the RAM the snapshot names" do
      expect(described_class.new(ram: :expanded).snapshot.load.ram_kb).to eq(53)
    end

    # A KIM-1 with every switch and wire on, saved and loaded.
    def switched
      described_class.new.tap do |kim|
        kim.sst = true
        kim.irq_wired = true
        kim.speaker = true
        kim.tty = true
      end.snapshot.load
    end

    it "keeps the switches and the wiring" do
      machine = switched
      expect([machine.sst, machine.irq_wired, machine.speaker?, machine.tty?]).to eq([true, true, true, true])
    end

    it "keeps U3's timer's interrupt flag" do
      machine = described_class.new.tap do |kim|
        kim.poke(0x170c, 1)
        kim.run_cycles(3)
      end.snapshot.load
      expect(machine.u3.irq?).to be(true)
    end

    it "keeps the keys still to press" do
      machine = typing.snapshot.load
      machine.run_cycles(200_000) while machine.typing?
      expect([machine.peek(0x0200), machine.display_text]).to eq([0xa9, "0200 A9"])
    end

    # A KIM-1 that has started to press AD 0200 DA A9.
    def typing
      described_class.new.tap do |kim|
        kim.type_keys("AD 0200 DA A9")
        kim.run_cycles(described_class::BOOT_CYCLES + 1)
      end
    end

    # Three periods of 3,700 Hz and one of 2,400 Hz.
    def crossings = [100, 235, 370, 505, 640, 848, 1056]

    # A KIM-1 whose deck has played 500 microseconds into a tape, through
    # PB7's first edge, saved and loaded.
    def playing
      described_class.new.tap do |kim|
        kim.tape.insert_tape(Badline::Storage::KIMTape.new("dump.wav", crossings:))
        kim.tape.play
        kim.run_cycles(500)
        kim.tape.input
      end.snapshot.load
    end

    it "keeps the tape in the deck, and where it plays" do
      deck = playing.tape
      expect([deck.tape.path, deck.tape.crossings, deck.playing?,
              deck.position]).to eq(["dump.wav", crossings, true, 500])
    end

    it "plays on from PB7's level when saved" do
      machine = playing
      levels = [machine.tape.input]
      machine.run_cycles(500)
      expect(levels << machine.tape.input).to eq([0x7f, 0xff])
    end

    it "keeps a recording going" do
      machine = described_class.new.tap { |kim| kim.tape.record }.snapshot.load
      expect(machine.tape.recording?).to be(true)
    end

    it "refuses to restore into a machine built another way" do
      expect { described_class.new.restore(saved.snapshot) }
        .to raise_error(Badline::Snapshot::FormatError, /KIM-1 with 5K RAM, not a KIM-1 with 1K RAM/)
    end

    it "refuses to export for VICE" do
      expect { saved.export_snapshot(path) }.to raise_error(Badline::Snapshot::FormatError, /VICE has no KIM-1/)
    end
  end
end
