# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

describe Badline::Audio::Renderer do
  subject(:renderer) do
    described_class.new(tune, seconds: 0.05, rate: 8000, **options)
  end

  let(:dir) { Dir.mktmpdir }
  let(:tune) { Badline::Storage::SIDFile.new(tune_path) }
  let(:options) { {} }
  let(:signature) { "PSID" }
  let(:play) { load_address + 0x40 }

  before { File.binwrite(tune_path, (header + image).pack("C*")) }
  after { FileUtils.remove_entry(dir) }

  def tune_path = File.join(dir, "tune.sid")
  def load_address = 0x1000
  def output(name) = File.join(dir, name)
  def samples(name) = File.binread(output(name))[44..].unpack("s<*")

  # The RC network needs a moment to shed the mixer's DC step, so an
  # ungated voice only reads as silence in the second half.
  def steady_peak(name)
    data = samples(name)
    data[(data.length / 2)..].map(&:abs).max
  end

  def write(addr, value) = [0xa9, value, 0x8d, addr & 0xff, addr >> 8]

  # init sets up a triangle voice but gates it only when the song index is
  # non-zero, so the rendered audio says which subtune ran. play is an RTS.
  def init
    [0xaa] + write(0xd418, 0x0f) + write(0xd400, 0x21) + write(0xd401, 0x11) +
      write(0xd405, 0x00) + write(0xd406, 0xf0) +
      [0x8a, 0xf0, 0x05] + write(0xd404, 0x11) + [0x60]
  end

  def image
    init + ([0xea] * (0x40 - init.length)) + [0x60]
  end

  def header
    fields = { version: 2, data_offset: 0x7c, load: load_address,
               init: load_address, play:, songs: 2, start_song: 1 }
    words = fields.values.flat_map { |value| [value >> 8, value & 0xff] }
    signature.bytes + words + ([0] * 4) + texts +
      [0x00, 0x04, 0x00, 0x01, 0x00, 0x00]
  end

  def texts
    %w[TUNE AUTHOR 1987].flat_map { |t| t.bytes + ([0] * (32 - t.length)) }
  end

  describe "#player" do
    it "runs a PSID tune on the bare rig" do
      expect(renderer.player).to be_a(Badline::Audio::BarePlayer)
    end

    context "with an RSID tune" do
      let(:signature) { "RSID" }

      it "runs it on the whole machine" do
        expect(renderer.player).to be_a(Badline::Audio::MachinePlayer)
      end
    end

    context "with a tune that installs its own interrupt" do
      let(:play) { 0 }

      it "runs it on the whole machine" do
        expect(renderer.player).to be_a(Badline::Audio::MachinePlayer)
      end
    end
  end

  describe "#render" do
    it "writes as many samples as the length asks for" do
      renderer.render(output("out.wav"))
      expect(samples("out.wav").length).to eq(400)
    end

    it "writes an AIFF when the extension asks for one" do
      renderer.render(output("out.aiff"))
      expect(File.binread(output("out.aiff"))[0, 4]).to eq("FORM")
    end

    it "refuses a container it can't write" do
      expect { renderer.render(output("out.ogg")) }
        .to raise_error(described_class::UnknownFormatError, /\.ogg/)
    end

    it "reports the seconds rendered" do
      progress = []
      renderer.render(output("out.wav")) { |seconds| progress << seconds }
      expect(progress.last).to be_within(0.001).of(0.05)
    end

    it "runs the tune's init routine" do
      renderer.render(output("out.wav"))
      expect(samples("out.wav").map(&:abs).max).to be_positive
    end

    context "with the tune's own start song" do
      let(:options) { { seconds: 0.1 } }

      it "leaves the gated voice silent" do
        renderer.render(output("out.wav"))
        expect(steady_peak("out.wav")).to be < 2000
      end
    end

    context "with a tune living under the BASIC ROM" do
      def load_address = 0xa000

      it "banks the ROM out before calling the tune" do
        renderer.render(output("out.wav"))
        expect(samples("out.wav").map(&:abs).max).to be_positive
      end
    end

    context "with a subtune selected" do
      let(:options) { { song: 2, seconds: 0.1 } }

      it "plays the song it was given" do
        renderer.render(output("out.wav"))
        expect(steady_peak("out.wav")).to be > 3000
      end
    end
  end
end
