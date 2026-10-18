# frozen_string_literal: true

require "spec_helper"
require "badline/support"
require "badline/support/cbm2_checkpoint"

# The fixtures: xcbm2 3.10 on macOS, run with -default and -model 610 or
# 710, booted to READY, then given a program at $0400 of segment 15
# through the remote monitor and saved with `dump` where it starts
# sampling, and gzipped. With IRQs off, the program starts CIA timer A
# continuous from $1234, and 128 times keeps its low byte at $0500,X and
# TPI1's latches at $0580,X, clearing them, then stops in a JMP to itself
# at $0440. Each .samples file holds the 256 bytes xcbm2 left there once
# it reached that JMP, 25,945 cycles on. The mains latches once in each,
# where xcbm2 ticks it as its CRTC's vertical sync ends.
describe Badline::Snapshot::Vice::CBM2 do
  def fixture(name) = File.expand_path("../../../fixtures/#{name}", __dir__)

  def image(container) = Badline::Snapshot::Image.new(container)

  def xcbm2(model) = Badline::Snapshot::Container.parse(File.binread(fixture("xcbm2-#{model}-probe.vsf.gz")))

  def load(model) = image(xcbm2(model)).load { nil }

  def run_to(machine, address)
    start = machine.cycles
    machine.cycle! until machine.cpu.boundary? && machine.cpu.program_counter == address
    [machine.cycles - start, Array.new(0x100) { |offset| machine.bus.peek_bank(15, 0x500 + offset) }]
  end

  # The VICE modules alone of the machine's snapshot for VICE.
  def exported(machine)
    sections = Badline::Snapshot::Image.exported(machine).sections.reject { |section| section.name.start_with?("BL-") }
    Badline::Snapshot::Container.new(sections, machine: Badline::Snapshot::Container::CBM2)
  end

  def with_section(container, name)
    sections = container.sections.map { |section| section.name == name ? yield(section) : section }
    Badline::Snapshot::Container.new(sections, machine: container.machine)
  end

  def patched(section, offset, bytes)
    data = section.data.dup
    bytes.each_with_index { |byte, index| data.setbyte(offset + index, byte) }
    section.with(data:)
  end

  def keyed(machine, name) = Badline::Snapshot::Keyed::Reader.parse(machine.save_modules.find { |s| s.name == name })

  %w[610 710].each do |model|
    context "with xcbm2's snapshot of a #{model} running a program" do
      it "builds the #{model} at 50 Hz" do
        machine = load(model)
        expect([machine.model.name, machine.mains_hz, machine.kernal]).to eq([model, 50, "04a"])
      end

      it "runs the program as xcbm2 did, the mains' tick and the CIA's timer cycle for cycle" do
        expect(run_to(load(model), 0x0440)).to eq([25_945, File.binread(fixture("xcbm2-#{model}-probe.samples")).bytes])
      end
    end
  end

  it "reports the modules badline doesn't read" do
    lines = []
    image(xcbm2("610")).load { |line| lines << line }
    expect(lines.map { |line| line.split.first }).to include("CBM2CART", "DRIVE8", "DRIVECPU0", "KEYBOARD")
  end

  describe ".export" do
    it "writes the modules xcbm2 reads, in its order" do
      expect(exported(load("610")).sections.map(&:name))
        .to eq(%w[MAINCPU CBM2MEM CBM2CART CRTC CIA1 TPI1 TPI2 Acia1 SID SIDEXTENDED FSDRIVE TAPEPORT USERPORT])
    end

    it "writes each module at the version and size xcbm2 3.10 writes for a 610" do
      sizes = exported(load("610")).sections.to_h { |section| [section.to_s, section.data.bytesize] }
      expect(sizes).to eq("MAINCPU 1.3" => 79, "CBM2MEM 1.0" => 135_173, "CBM2CART 0.1" => 1, "CRTC 1.2" => 190_160,
                          "CIA1 2.3" => 52, "TPI1 1.0" => 10, "TPI2 1.0" => 10, "Acia1 1.1" => 22, "SID 1.5" => 36,
                          "SIDEXTENDED 1.4" => 133, "FSDRIVE 0.0" => 258, "TAPEPORT 1.0" => 2, "USERPORT 1.0" => 2)
    end

    it "writes a 700's picture and a 256K board at the sizes xcbm2 writes" do
      sections = exported(Badline::CBM2.new(model: "720")).sections
      expect(sections.select { |s| %w[CBM2MEM CRTC].include?(s.name) }.map { |s| s.data.bytesize })
        .to eq([266_245, 260_560])
    end

    it "names the file format xcbm2 reads, 1.0, and the machine CBM-II" do
      expect(exported(Badline::CBM2.new).to_s.byteslice(19, 18)).to eq("\x01\x00CBM-II".b + ("\0" * 10))
    end

    it "writes the model line and the segment registers ahead of the RAM" do
      machine = Badline::CBM2.new(mains_hz: 60)
      expect(exported(machine)["CBM2MEM"].data.bytes.first(7)).to eq([1, 0, 1, 15, 15, 15, 15])
    end

    it "writes the same modules again for a machine read from them" do
      machine = load("710")
      machine.run_cycles(12_345)
      first = exported(machine)
      expect(exported(image(first).load { nil }).to_s).to eq(first.to_s)
    end
  end

  describe ".setup" do
    def memory(container, offset, bytes)
      with_section(container, "CBM2MEM") { |section| patched(section, offset, bytes) }
    end

    it "builds a 600 at 60 Hz for its model line 1" do
      expect(described_class.setup(memory(xcbm2("610"), 2, [1])).mains_hz).to eq(60)
    end

    it "builds a 620 for a 256K board" do
      expect(described_class.setup(memory(xcbm2("610"), 0, [2])).model).to eq("620")
    end

    it "refuses a board badline doesn't build" do
      expect { described_class.setup(memory(xcbm2("610"), 0, [4])) }
        .to raise_error(Badline::Snapshot::FormatError, /512K of RAM, which badline doesn't build/)
    end

    it "refuses RAM mapped into segment 15" do
      expect { described_class.setup(memory(xcbm2("610"), 1, [0x21])) }
        .to raise_error(Badline::Snapshot::FormatError, /RAM in segment 15/)
    end
  end

  describe "modules as xcbm2 writes them" do
    # xcbm2's TPI1 with I0 and I2 latched and I2 in the AIR, in mode 1
    # with priority, CA low and CB high.
    let(:tpi) do
      Badline::Snapshot::Section.new(name: "TPI1", major: 1, minor: 0,
                                     data: [0x38, 0xff, 0x05, 0x3f, 0x7d, 0xff, 0xe3, 0x04, 0x05, 0x40].pack("C*"))
    end

    # xcbm2's ACIA with control $1E and command $0B, after $55 was written
    # and before its character time ran out.
    let(:acia) do
      Badline::Snapshot::Section.new(name: "Acia1", major: 1, minor: 1,
                                     data: ([0x55, 0x00, 0x60, 0x0b, 0x1e, 0x02, 0x23, 0x08, 0, 0, 0, 0, 0, 0,
                                             0x23, 0x08] + ([0] * 6)).pack("C*"))
    end

    it "takes the TPI's latches, mask and AIR from PRC, DDRC and the AIR, with no interrupt in service" do
      machine = image(with_section(xcbm2("610"), "TPI1") { tpi }).load { nil }
      fields = keyed(machine, "BL-TPI1")
      expect([fields.int("latches", 0), fields.int("mask", 0), fields.int("air", 0), fields.ints("stack", [9])])
        .to eq([0x05, 0x1f, 0x04, []])
    end

    it "takes CA from bit 7 of the TPI's last byte and CB from bit 6" do
      machine = image(with_section(xcbm2("610"), "TPI1") { tpi }).load { nil }
      expect([machine.tpi1.ca?, machine.tpi1.cb?]).to eq([false, true])
    end

    it "takes the ACIA's registers and the byte waiting to be sent" do
      fields = keyed(image(with_section(xcbm2("610"), "Acia1") { acia }).load { nil }, "BL-ACIA")
      expect([fields.int("command", 0), fields.int("control", 0), fields.int("transmit_data", 0),
              fields.bool("transmitter_empty", true)]).to eq([0x0b, 0x1e, 0x55, false])
    end

    it "shows the cursor where xcbm2 shows it" do
      shown = image(with_section(xcbm2("610"), "CRTC") { |s| patched(s, 0x28, [1]) }).load { nil }
      hidden = image(with_section(xcbm2("610"), "CRTC") { |s| patched(s, 0x28, [0]) }).load { nil }
      expect([shown, hidden].map { |m| keyed(m, "BL-VIDEO").int("frames", 0).nobits?(0x10) }).to eq([true, false])
    end
  end

  describe "restored into a running CBM-II" do
    it "runs on as a new machine restored from it does" do
      target = Badline::CBM2.new.tap { |machine| machine.run_cycles(1_001) }
      image(xcbm2("610")).restore(target) { nil }
      expect(Badline::Support::CBM2Checkpoint.take(target)).to eq(Badline::Support::CBM2Checkpoint.take(load("610")))
    end

    it "fails for a CBM-II built another way" do
      expect { image(xcbm2("610")).restore(Badline::CBM2.new(model: "620")) }
        .to raise_error(Badline::Snapshot::FormatError, /of a 610 with KERNAL 04a at 50 Hz, not a 620/)
    end

    it "fails for another machine" do
      expect { image(xcbm2("610")).restore(Badline::C64.new) }
        .to raise_error(Badline::Snapshot::FormatError, /of a CBM-II, not a C64/)
    end

    it "fails on a MAINCPU version it doesn't know" do
      newer = with_section(xcbm2("610"), "MAINCPU") { |section| section.with(minor: 4) }
      expect { image(newer).restore(Badline::CBM2.new) }
        .to raise_error(Badline::Snapshot::FormatError, /MAINCPU 1\.4: badline doesn't read this version/)
    end

    it "leaves out and reports another module's version it doesn't know" do
      lines = []
      newer = with_section(xcbm2("610"), "TPI2") { |section| section.with(minor: 9) }
      image(newer).restore(Badline::CBM2.new) { |line| lines << line }
      expect(lines).to include("TPI2 1.9: badline doesn't read this version, left out")
    end
  end
end
