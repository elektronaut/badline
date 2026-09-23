# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../support/tiny_sid"

describe Badline::Audio::Renderer do
  subject(:renderer) do
    described_class.new(tune, seconds: 0.05, rate: 8000, **options)
  end

  let(:dir) { Dir.mktmpdir }
  let(:tune) { Badline::Storage::SIDFile.new(tune_path) }
  let(:options) { {} }
  let(:signature) { "PSID" }
  let(:play) { load_address + 0x40 }

  before { File.binwrite(tune_path, TinySID.bytes(signature:, load_address:, play:)) }
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

  describe "the SID model" do
    it "defaults to a 6581" do
      expect(renderer.player.sid.model).to eq(:mos6581)
    end

    context "with an 8580 tune" do
      before { allow(tune).to receive(:sid_model).and_return(:mos8580) }

      it "fits the bare rig with an 8580" do
        expect(renderer.player.sid.model).to eq(:mos8580)
      end
    end

    context "with an 8580 tune on the whole machine" do
      let(:signature) { "RSID" }

      before { allow(tune).to receive(:sid_model).and_return(:mos8580) }

      it "fits the machine with an 8580" do
        expect(renderer.player.sid.model).to eq(:mos8580)
      end
    end

    context "with an override" do
      let(:options) { { sid_model: :mos6581 } }

      before { allow(tune).to receive(:sid_model).and_return(:mos8580) }

      it "takes the override over the tune's own" do
        expect(renderer.player.sid.model).to eq(:mos6581)
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
