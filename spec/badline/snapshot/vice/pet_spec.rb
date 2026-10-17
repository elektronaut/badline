# frozen_string_literal: true

require "spec_helper"
require "badline/support"
require "badline/support/pet_checkpoint"
require_relative "../../../support/xpet_snapshots"

describe Badline::Snapshot::Vice::PET do
  include XpetSnapshots

  def image(container) = Badline::Snapshot::Image.new(container)

  def machine(model = "8032", cycles = 30_000) = XpetSnapshots.probing(model, cycles).load

  def container(model = "8032", cycles = 30_000) = XpetSnapshots.exported(machine(model, cycles))

  def cpu_registers(pet)
    cpu = pet.cpu
    [pet.cycles, cpu.program_counter, cpu.a, cpu.x, cpu.y, cpu.stack_pointer, cpu.p]
  end

  def checkpoint(pet) = Badline::Support::PETCheckpoint.take(pet)

  def section_bytes(container) = container.sections.to_h { |section| [section.to_s, section.data.bytesize] }

  describe ".export" do
    it "writes the modules xpet needs, in its order" do
      expect(container.sections.map(&:name))
        .to eq(%w[MAINCPU CPU6809 PETMEM CRTC PIA1 PIA2 VIA FSDRIVE TAPEPORT USERPORT])
    end

    it "writes each module at the version and size xpet 3.10 writes for an 8032" do
      expect(section_bytes(container)).to eq("MAINCPU 1.3" => 79, "CPU6809 1.1" => 27, "PETMEM 1.3" => 34_845,
                                             "CRTC 1.2" => 194_384, "PIA1 1.0" => 7, "PIA2 1.0" => 7, "VIA 2.2" => 28,
                                             "FSDRIVE 0.0" => 258, "TAPEPORT 1.0" => 3, "USERPORT 1.0" => 2)
    end

    it "writes the sizes xpet writes for a 2001's PETMEM and CRTC" do
      expect(section_bytes(container("2001")).values_at("PETMEM 1.3", "CRTC 1.2")).to eq([9245, 84_560])
    end

    it "writes an 8096's board after the screen RAM" do
      expect(section_bytes(container("8096"))["PETMEM 1.3"]).to eq(100_381)
    end

    it "names the file format xpet reads, 1.0, and the machine PET" do
      expect(container.to_s.byteslice(19, 18)).to eq("\x01\x00PET".b + ("\0" * 13))
    end
  end

  describe "a machine restored from xpet's modules alone" do
    %w[8032 4032 2001 8096].each do |model|
      it "runs on as the saved #{model} does, the picture too once two frames are drawn" do
        saved = machine(model)
        restored = image(XpetSnapshots.exported(saved)).load { nil }
        XpetSnapshots.run(saved, 45_001)
        XpetSnapshots.run(restored, 45_001)
        expect(checkpoint(restored).differences(checkpoint(saved))).to eq([])
      end
    end

    it "has the CPU's registers and the clock" do
      saved = machine
      expect(cpu_registers(image(XpetSnapshots.exported(saved)).load { nil })).to eq(cpu_registers(saved))
    end

    it "has the 8096's board and its control register" do
      saved = machine("8096")
      [[0xfff0, 0x80], [0x9000, 0x55], [0xfff0, 0xcc]].each { |at, value| saved.poke(at, value) }
      restored = image(XpetSnapshots.exported(saved)).load { nil }
      expect([restored.bus.expansion.control, restored.bus.expansion.cells]).to eq([0xcc, saved.bus.expansion.cells])
    end

    it "reports the modules badline doesn't read" do
      lines = []
      image(container).load { |line| lines << line }
      expect(lines.map { |line| line.split.first }).to eq(%w[CPU6809 FSDRIVE TAPEPORT USERPORT])
    end
  end

  describe "a snapshot badline reads and writes again" do
    [25_001, 31_337, 38_700, 41_950].each do |cycles|
      it "writes the same modules for an 8032 #{cycles} cycles in" do
        exported = container("8032", cycles)
        again = XpetSnapshots.exported(image(exported).load { nil })
        expect(again.sections.map(&:data)).to eq(exported.sections.map(&:data))
      end
    end

    it "writes the same modules for a 2001" do
      exported = container("2001", 25_001)
      expect(XpetSnapshots.exported(image(exported).load { nil }).to_s).to eq(exported.to_s)
    end
  end

  describe ".setup" do
    def setup(container) = described_class.setup(container)

    def crtc_registers(registers) = ->(section) { XpetSnapshots.patched(section, 0x0f, registers) }

    it "builds an 8032 with xpet's 50 Hz editor, 901474-04 dated 0283, for its 64-cycle lines" do
      patched = XpetSnapshots.with_section(container, "CRTC", &crtc_registers([0x3f, 0x28, 0x32, 0x08, 0x20, 0x10]))
      expect(setup(patched).editor).to eq("pet/editor4-80-b-50hz-0283.rom")
    end

    it "runs a CRTC board's editor at 60 Hz for a frame of 333 lines" do
      patched = XpetSnapshots.with_section(container, "CRTC", &crtc_registers([0x31, 0x28, 0x29, 0x0f, 0x20, 0x03]))
      expect(setup(patched).refresh_hz).to eq(60)
    end

    it "builds a 2001 where xpet's settings name one" do
      expect(setup(container("2001")).model).to eq("2001")
    end

    it "builds a 3032 for any other discrete board" do
      expect(setup(container("3032b")).model).to eq("3032")
    end

    it "refuses a SuperPET" do
      superpet = XpetSnapshots.with_section(container, "PETMEM") { |section| XpetSnapshots.patched(section, 0, [3]) }
      expect { setup(superpet) }.to raise_error(Badline::Snapshot::FormatError, /SuperPET, which badline doesn't build/)
    end
  end

  describe "restored into a running PET" do
    def with_module(name, major, minor)
      exported = container
      extra = Badline::Snapshot::Section.new(name:, major:, minor:, data: "x")
      Badline::Snapshot::Container.new(exported.sections + [extra], machine: exported.machine)
    end

    it "runs on as a new machine restored from it does" do
      target = XpetSnapshots.run(Badline::PET.new, 1_001)
      image(container).restore(target) { nil }
      restored = image(container).load { nil }
      expect(checkpoint(target)).to eq(checkpoint(restored))
    end

    it "fails for a PET built another way" do
      expect { image(container).restore(Badline::PET.new(model: "4032")) }
        .to raise_error(Badline::Snapshot::FormatError, /the snapshot is of a 8032 with 32K at 50 Hz, not a 4032/)
    end

    it "fails for another machine" do
      expect { image(container).restore(Badline::C64.new) }
        .to raise_error(Badline::Snapshot::FormatError, /of a PET, not a C64/)
    end

    it "reports a module badline doesn't read" do
      lines = []
      image(with_module("DRIVE8", 2, 0)).restore(Badline::PET.new) { |line| lines << line }
      expect(lines).to include("DRIVE8 2.0: badline doesn't read this module, left out")
    end

    it "fails on a MAINCPU version it doesn't know" do
      newer = XpetSnapshots.with_section(container, "MAINCPU") { |section| section.with(minor: 4) }
      expect { image(newer).restore(Badline::PET.new) }
        .to raise_error(Badline::Snapshot::FormatError, /MAINCPU 1\.4: badline doesn't read this version/)
    end

    it "leaves out and reports another module's version it doesn't know" do
      lines = []
      newer = XpetSnapshots.with_section(container, "VIA") { |section| section.with(minor: 9) }
      image(newer).restore(Badline::PET.new) { |line| lines << line }
      expect(lines).to include("VIA 2.9: badline doesn't read this version, left out")
    end
  end

  describe "modules as xpet writes them" do
    # xpet 3.10's VIA after a program wrote DDRA $A5, ORA $3C, PCR $CC,
    # timer 1 from $5678 with its latch then $1234, timer 2 from $9ABC,
    # SR $C3 and IER $A2.
    let(:via) do
      Badline::Snapshot::Section.new(name: "VIA", major: 2, minor: 2,
                                     data: [0x3c, 0xa5, 0xdf, 0x1e, 0x34, 0x12, 0x78, 0x56, 0xbc, 0x9a, 0xbc, 0x9a,
                                            0xbc, 0x9a, 0xc0, 0xc3, 0x00, 0xcc, 0x00, 0x22, 0x00, 0x03, 0x60, 0x00,
                                            0x00, 0x01, 0x00, 0x00].pack("C*"))
    end
    let(:restored) { image(XpetSnapshots.with_section(container, "VIA") { via }).load { nil }.via }

    it "puts the VIA's timers where a read on the next cycle finds xpet's counts" do
      expect([restored.timer1, restored.timer1_latch, restored.timer2]).to eq([0x5679, 0x1234, 0x9abd])
    end

    it "puts the VIA's registers and its CA2 level in place" do
      expect([restored.pcr, restored.interrupt_enable, restored.shift_register.data, restored.ca2_output])
        .to eq([0xcc, 0xa2, 0xc3, false])
    end

    it "takes a PIA's flags from its control registers" do
      pia = Badline::Snapshot::Section.new(name: "PIA1", major: 1, minor: 0,
                                           data: [0xf9, 0x0f, 0x3c, 0xff, 0x00, 0xbc, 0xc0].pack("C*"))
      restored = image(XpetSnapshots.with_section(container, "PIA1") { pia }).load { nil }
      expect([restored.pia1.cra, restored.pia1.crb]).to eq([0x3c, 0xbc])
    end
  end
end
