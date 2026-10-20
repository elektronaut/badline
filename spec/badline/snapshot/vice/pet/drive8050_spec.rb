# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require_relative "../../../../support/xpet_snapshots"

# The fixture: xpet 3.10 on macOS, run with -default -model 8032
# -drive8type 8050 -drive8truedrive and a .d80 c1541 formatted "test,01"
# as -8, booted to READY and saved with `dump` from the remote monitor,
# and gzipped. Its 8050 has read nothing from the disk yet.
describe Badline::Snapshot::Vice::PET::Drive8050 do
  include XpetSnapshots

  def image(container) = Badline::Snapshot::Image.new(container)

  def fixture = File.expand_path("../../../../fixtures/xpet310-8050.vsf.gz", __dir__)

  def xpet = Badline::Snapshot::Container.parse(File.binread(fixture))

  def blank_d80(dir)
    File.join(dir, "blank.d80").tap do |path|
      File.binwrite(path, "\0" * 533_248)
      Badline::Storage::D80Image.new(path).format("test", "01".bytes)
    end
  end

  # A PET built as xpet's, with an 8050 holding a blank disk, restored
  # from the fixture.
  def restored(dir)
    pet = Badline::Snapshot::Vice::PET.setup(xpet).build
    drive = Badline::Drives::Model8050.new
    pet.attach_ieee_drive(drive)
    drive.insert_image(blank_d80(dir))
    image(xpet).restore(pet) { nil }
    pet
  end

  def cpu(container) = container[described_class::CPU].data

  def section_bytes(container) = container.sections.to_h { |section| [section.to_s, section.data.bytesize] }

  it "reads the model from DRIVE8's type" do
    expect(described_class.model(xpet)).to eq("8050")
  end

  describe "a PET with an 8050 restored from xpet's modules", :slow do
    let(:dir) { Dir.mktmpdir }
    let(:pet) { restored(dir) }

    it "has the interface processor's registers" do
      ip = pet.true_drive.ip_cpu
      header = cpu(xpet).bytes
      expect([ip.a, ip.x, ip.y, ip.stack_pointer, ip.program_counter, ip.p])
        .to eq([*header[8, 4], header[12] | (header[13] << 8), header[14]])
    end

    it "has the common RAM" do
      common = pet.true_drive.common
      expect(Array.new(0x1000) { |index| common.peek(index) }).to eq(cpu(xpet).bytes[0x5c + 0x100, 0x1000])
    end

    it "has the 6532s' RAM, the interface processor's page 0" do
      riots = pet.true_drive
      expect(riots.data_riot.ram + riots.control_riot.ram).to eq(cpu(xpet).bytes[0x5c, 0x100])
    end

    it "has UE1's ports and its PA7 edge" do
      riot = pet.true_drive.control_riot
      fields = Badline::Snapshot::Keyed::Reader.parse(pet.save_modules.find { |s| s.name == "BL-D8-RIOT2" })
      expect([fields.int("ora", 0), fields.int("ddra", 0), fields.bool("edge_irq_enabled", false),
              fields.bool("rising_edge", false), riot.ram.length]).to eq([0x1c, 0x1f, true, true, 128])
    end

    it "puts the controller in its idle loop" do
      fdc = pet.true_drive.fdc_cpu
      expect([fdc.program_counter, fdc.boundary?]).to eq([Badline::Drives::Model8050::Idle::FDC_LOOP, true])
    end

    it "keeps the disk" do
      expect(pet.true_drive.disk&.image&.path).to eq(File.join(dir, "blank.d80"))
    end

    it "lists the disk's directory" do
      pet.type_text("load\"$\",8\rlist\r")
      pet.run_cycles(8_000_000)
      screen = Array.new(25 * 80) { |index| pet.peek(0x8000 + index) & 0x7f }
      expect(screen.pack("C*")).to include("\x14\x05\x13\x14".b)
    end
  end

  describe ".export", :slow do
    let(:exported) { Dir.mktmpdir { |dir| XpetSnapshots.exported(restored(dir)) } }

    it "follows the VIA in xpet's order" do
      expect(exported.sections.map(&:name))
        .to eq(%w[MAINCPU CPU6809 PETMEM CRTC PIA1 PIA2 VIA DRIVE8 DRIVE9 DRIVE10 DRIVE11 DRIVECPU0 RIOT1D0 RIOT2D0
                  FDC0 FSDRIVE TAPEPORT USERPORT])
    end

    it "has the versions and sizes xpet 3.10 writes" do
      expect(section_bytes(exported).slice("DRIVE8 2.0", "DRIVECPU0 1.3", "RIOT1D0 0.0", "RIOT2D0 0.0", "FDC0 0.0"))
        .to eq("DRIVE8 2.0" => 284, "DRIVECPU0 1.3" => 4456, "RIOT1D0 0.0" => 12, "RIOT2D0 0.0" => 12,
               "FDC0 0.0" => 8)
    end

    it "writes the 6532s and the interface processor's RAM as it read them" do
      expect(%w[RIOT1D0 RIOT2D0].map { |name| exported[name].data } + [cpu(exported).byteslice(0x5c, 0x1100)])
        .to eq(%w[RIOT1D0 RIOT2D0].map { |name| xpet[name].data } + [cpu(xpet).byteslice(0x5c, 0x1100)])
    end
  end

  describe ".export of a unit's own modules" do
    # The readers of a unit of `model` at power-on, its controller, or its
    # SASI host, put at `counter`, by default at its idle loop.
    def readers(model, counter = described_class.controller_loop(model))
      sections = described_class.new_unit(model).save_modules([], "BL-D8")
      host = described_class.hard_disk?(model) ? "BL-D8-SASICPU" : "BL-D8-FDCCPU"
      sections << Badline::Snapshot::Keyed.section(host) { |out| out.int("pc", counter) }
      sections.to_h { |section| [section.name, Badline::Snapshot::Keyed::Reader.parse(section)] }
    end

    def idle_loop = Badline::Drives::Model8050::Idle::FDC_LOOP

    def unit(model) = described_class.export(Badline::PET.new, readers(model)).first

    def type_word(bytes) = bytes.byteslice(described_class::TYPE, 2).unpack1("v")

    it "names the 8250 in DRIVE8 for an 8250" do
      unit = described_class.export(Badline::PET.new, readers("8250", idle_loop)).first
      expect(unit.data.byteslice(described_class::TYPE, 2).unpack1("v")).to eq(8250)
    end

    it "puts each head's half track in its drive's block" do
      unit = described_class.export(Badline::PET.new, readers("8050", idle_loop)).first
      expect([0, described_class::BLOCK].map { |at| unit.data.getbyte(at + described_class::HALF_TRACK) }).to eq([2, 2])
    end

    it "writes one drive's block for a 1001, as xpet's type 1001" do
      unit = described_class.export(Badline::PET.new, readers("1001", idle_loop)).first
      expect([unit.data.bytesize, unit.data.getbyte(1), unit.data.byteslice(described_class::TYPE, 2).unpack1("v")])
        .to eq([145, 1, 1001])
    end

    it "leaves the drive out while its controller is away from its idle loop" do
      expect(described_class.export(Badline::PET.new, readers("8050", 0xfc00))).to eq([])
    end

    it "names the 2040 in DRIVE8 as xpet's type 2040, once its controller is in DOS 1's job loop" do
      expect(type_word(unit("2040").data)).to eq(2040)
    end

    it "puts a 4040's heads on track 1 at half track 2" do
      section = unit("4040")
      expect([0, described_class::BLOCK].map { |at| section.data.getbyte(at + described_class::HALF_TRACK) })
        .to eq([2, 2])
    end

    it "writes a D9060 and a D9090 as xpet's type 9000, one block with the head where xpet keeps it" do
      data = %w[9060 9090].map { |model| unit(model).data }
      expect(data.map { |bytes| [bytes.bytesize, type_word(bytes), bytes.getbyte(described_class::HALF_TRACK)] })
        .to eq([[145, 9000, 0x98]] * 2)
    end

    it "leaves a hard disk out while its SASI host is away from its job loop" do
      expect(described_class.export(Badline::PET.new, readers("9060", 0xf800))).to eq([])
    end
  end

  describe "the hard disk badline keeps" do
    def kept(heads) = Badline::Snapshot::Keyed.section("BL-D8-SASI") { |out| out.int("disk_heads", heads) }

    it "makes the unit a D9090 for an image with six heads, and otherwise a D9060" do
      expect([kept(6), kept(4), nil].map { |section| described_class.hard_disk_model([section].compact) })
        .to eq(%w[9090 9060 9060])
    end

    it "keeps the disks of a unit of the same xpet type" do
      expect([%w[9060 9090], %w[4040 3040], %w[8050 8050]].map { |pair| described_class.same_type?(*pair) })
        .to eq([true, false, true])
    end
  end
end
