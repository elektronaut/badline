# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

# The fixtures: xpet 3.10 on macOS, run with -default -model 8032 -warp
# -drive8truedrive and -drive8type 4040 with VICE-testprogs'
# vdrive/test.d64 as -8, or -drive8type 9000 with a .d90 badline
# formatted "hard", booted, made to list the directory with DIRECTORY,
# saved with `dump` from the remote monitor, and gzipped.
describe Badline::Snapshot::Vice::PET::Drive8050 do
  def fixture(type) = File.expand_path("../../../../fixtures/xpet310-#{type}.vsf.gz", __dir__)

  def xpet(type) = Badline::Snapshot::Container.parse(Zlib.gunzip(File.binread(fixture(type))))

  # A PET built as xpet's, with a unit of `model` holding `image`, if
  # any, restored from the fixture of xpet's `type`.
  def restored(type, model, image = nil)
    container = xpet(type)
    pet = Badline::Snapshot::Vice::PET.setup(container).build
    drive = pet.plug_ieee_drive(model)
    drive.insert_image(image) if image
    Badline::Snapshot::Image.new(container).restore(pet) { nil }
    pet
  end

  # A unit of `model` at power-on, for the controller's side of a restore
  # that doesn't look at it, in place of one run into its idle loop.
  def unbooted(model) = described_class.new_unit(model).save_modules([], "BL-D8")

  it "reads xpet's types 4040 and 9000 as the 4040 and the D9060" do
    expect(%w[4040 9000].map { |type| described_class.model(xpet(type)) }).to eq(%w[4040 9060])
  end

  it "gives a 4040 the interface processor's registers from xpet's modules", :slow do
    allow(described_class).to receive(:reference).with("4040").and_return(unbooted("4040"))
    ip = restored("4040", "4040").true_drive.ip_cpu
    header = xpet("4040")[described_class::CPU].data.bytes
    expect([ip.a, ip.x, ip.y, ip.stack_pointer, ip.program_counter, ip.p])
      .to eq([*header[8, 4], header[12] | (header[13] << 8), header[14]])
  end

  describe "a PET with a D9060 restored from xpet's modules", :slow do
    let(:dir) { Dir.mktmpdir }
    let(:image) { File.join(dir, "hard.d90").tap { |path| File.binwrite(path, "\0" * 5_013_504) } }

    after { FileUtils.remove_entry(dir) }

    it "keeps the hard disk" do
      allow(described_class).to receive(:reference).with("9060").and_return(unbooted("9060"))
      expect(restored("9000", "9060", image).true_drive.disk&.path).to eq(image)
    end

    it "puts the SASI host in its job loop" do
      host = restored("9000", "9060", image).true_drive.sasi_cpu
      expect([host.program_counter, host.boundary?]).to eq([Badline::Drives::Model9060::Idle::SASI_LOOP, true])
    end
  end
end
