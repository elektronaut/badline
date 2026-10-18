# frozen_string_literal: true

require "spec_helper"
require "badline/support"
require "badline/support/cbm2_checkpoint"
require "badline/support/p500_checkpoint"

# The fixture: xcbm5x0 3.10 on macOS, run with -default -model 510,
# booted to READY, then given the program the xcbm2 fixtures run (see
# cbm2_spec.rb) at $0400 of segment 15 through the remote monitor and
# saved with `dump` where it starts sampling, and gzipped. The .samples
# file holds the 256 bytes xcbm5x0 left at $0500, CIA timer A's low byte
# and then TPI1's latches, once it reached the JMP at $0440, 27,708 cycles
# on. The mains latches once, 82 samples in.
describe Badline::Snapshot::Vice::P500 do
  def fixture(name) = File.expand_path("../../../fixtures/#{name}", __dir__)

  def image(container) = Badline::Snapshot::Image.new(container)

  def xcbm5x0 = Badline::Snapshot::Container.parse(File.binread(fixture("xcbm5x0-510-probe.vsf.gz")))

  def load = image(xcbm5x0).load { nil }

  def samples = File.binread(fixture("xcbm5x0-510-probe.samples")).bytes

  def run_to(machine, address)
    start = machine.cycles
    machine.cycle! until machine.cpu.boundary? && machine.cpu.program_counter == address
    [machine.cycles - start, Array.new(0x100) { |offset| machine.bus.peek_bank(15, 0x500 + offset) }]
  end

  # The VICE modules alone of the machine's snapshot for VICE.
  def exported(machine)
    sections = Badline::Snapshot::Image.exported(machine).sections.reject { |section| section.name.start_with?("BL-") }
    Badline::Snapshot::Container.new(sections, machine: Badline::Snapshot::Container::CBM2_5X0)
  end

  def with_section(container, name)
    sections = container.sections.map { |section| section.name == name ? yield(section) : section }
    Badline::Snapshot::Container.new(sections, machine: container.machine)
  end

  context "with xcbm5x0's snapshot of a 510 running a program" do
    it "builds a PAL 510" do
      machine = load
      expect([machine.class, machine.model.name, machine.mains_hz]).to eq([Badline::CBM2::P500, "510", 50])
    end

    it "reaches the program's end on xcbm5x0's cycle, the mains latched where xcbm5x0 latched it" do
      cycles, sampled = run_to(load, 0x0440)
      expect([cycles, sampled[0x80, 0x80]]).to eq([27_708, samples[0x80, 0x80]])
    end

    it "has the VIC's registers and its beam" do
      vic = load.vic
      bytes = xcbm5x0["VIC-II"].data.bytes
      expect([vic.register_file.first(0x2f), vic.rasterline])
        .to eq([bytes[described_class::VICII::REGISTERS, 0x2f], bytes[0x45d] | (bytes[0x45e] << 8)])
    end

    it "has the colour RAM" do
      color_ram = load.color_ram
      expect(Array.new(0x400) { |offset| color_ram.nibble(0xd400 + offset) })
        .to eq(xcbm5x0["VIC-II"].data.bytes[described_class::VICII::COLOR_RAM, 0x400].map { |value| value & 0x0f })
    end

    it "has the video matrix in segment 15" do
      bus = load.bus
      expect(Array.new(0x400) { |offset| bus.peek_bank(15, 0xd000 + offset) })
        .to eq(xcbm5x0["CBM2MEM"].data.byteslice(0x805, 0x400).bytes)
    end
  end

  describe ".export" do
    let(:machine) { load.tap { |each| each.run_cycles(12_345) } }

    it "writes the modules xcbm5x0 reads, in its order" do
      expect(exported(machine).sections.map(&:name))
        .to eq(%w[MAINCPU CBM2MEM CBM2CART CIA1 TPI1 TPI2 Acia1 SID SIDEXTENDED FSDRIVE VIC-II C500DATA TAPEPORT
                  JOYPORT0 JOYSTICK0 JOYPORT1 JOYSTICK1])
    end

    it "writes CBM2MEM and the VIC-II at the sizes xcbm5x0 writes for a 510" do
      sizes = exported(machine).sections.to_h { |section| [section.to_s, section.data.bytesize] }
      expect(sizes.slice("CBM2MEM 1.0", "VIC-II 1.3", "C500DATA 0.0"))
        .to eq("CBM2MEM 1.0" => 135_173, "VIC-II 1.3" => 160_513, "C500DATA 0.0" => 8)
    end

    it "names the file format xcbm5x0 writes, 0.0, and the machine CBM-II-5x0" do
      expect(exported(machine).to_s.byteslice(19, 18)).to eq("\x00\x00CBM-II-5x0".b + ("\0" * 6))
    end

    it "writes the same modules again for a machine read from them" do
      first = exported(machine)
      expect(exported(image(first).load { nil }).to_s).to eq(first.to_s)
    end

    it "writes an NTSC 510's picture at the size xcbm5x0 writes" do
      sections = exported(Badline::CBM2::P500.new(model: "510ntsc")).sections
      expect(sections.find { |section| section.name == "VIC-II" }.data.bytesize).to eq(146_329)
    end
  end

  describe ".setup" do
    it "builds an NTSC 510 for NTSC's picture" do
      ntsc = image(exported(Badline::CBM2::P500.new(model: "510ntsc"))).load { nil }
      expect([ntsc.model.name, ntsc.mains_hz]).to eq(["510ntsc", 60])
    end

    it "refuses a P500 with more RAM" do
      bigger = with_section(xcbm5x0, "CBM2MEM") { |section| section.with(data: "\x02".b + section.data.byteslice(1..)) }
      expect { described_class.setup(bigger) }.to raise_error(Badline::Snapshot::FormatError, /128K of RAM/)
    end
  end

  describe "restored into a running P500" do
    it "runs on as a new machine restored from it does" do
      target = Badline::CBM2::P500.new.tap { |machine| machine.run_cycles(1_001) }
      image(xcbm5x0).restore(target) { nil }
      expect(Badline::Support::P500Checkpoint.take(target)).to eq(Badline::Support::P500Checkpoint.take(load))
    end

    it "fails for a B series" do
      expect { image(xcbm5x0).restore(Badline::CBM2.new) }
        .to raise_error(Badline::Snapshot::FormatError, /of a P500, not a CBM-II's B series/)
    end
  end
end
