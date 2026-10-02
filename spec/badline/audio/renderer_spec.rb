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

  before { File.binwrite(tune_path, TinySID.bytes(signature:, load_address:, play:, flags:, sids:)) }
  after { FileUtils.remove_entry(dir) }

  def tune_path = File.join(dir, "tune.sid")
  def load_address = 0x1000
  def flags = 0x04
  def sids = []
  def output(name) = File.join(dir, name)
  def channels(name) = File.binread(output(name))[44..].unpack("s<*").each_slice(2).to_a.transpose

  def samples(name) = channels(name).first

  # The RC network needs a moment to shed the mixer's DC step, so an
  # ungated voice only reads as silence in the second half.
  def steady_peak(name, channel = 0)
    data = channels(name)[channel]
    data[(data.length / 2)..].map(&:abs).max
  end

  def rising_crossings(name)
    data = samples(name)[1000..]
    mean = data.sum / data.length
    data.each_cons(2).count { |a, b| a < mean && b >= mean }
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
      let(:options) { { sid_models: [:mos6581] } }

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

    it "writes a stereo file" do
      renderer.render(output("out.wav"))
      expect(File.binread(output("out.wav"))[22, 2].unpack1("v")).to eq(2)
    end

    it "plays one SID the same on both channels" do
      renderer.render(output("out.wav"))
      expect(channels("out.wav").uniq.size).to eq(1)
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

    context "with the tune's own start subtune" do
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
      let(:options) { { subtune: 2, seconds: 0.1 } }

      it "plays the subtune it was given" do
        renderer.render(output("out.wav"))
        expect(steady_peak("out.wav")).to be > 3000
      end
    end

    context "with a silence to end on" do
      let(:options) { { seconds: 1 } }

      before { renderer.silence = 0.1 }

      it "ends once the output holds still" do
        renderer.render(output("out.wav"))
        expect(samples("out.wav").length).to be_between(800, 2400)
      end

      it "reports the seconds it rendered" do
        renderer.render(output("out.wav"))
        expect(renderer.rendered).to be_within(0.001).of(samples("out.wav").length / 8000.0)
      end
    end

    context "with a silence to end on and a subtune that keeps sounding" do
      let(:options) { { subtune: 2, seconds: 0.3 } }

      before { renderer.silence = 0.1 }

      it "plays the whole length" do
        renderer.render(output("out.wav"))
        expect(samples("out.wav").length).to eq(2400)
      end
    end

    context "with a second SID that only the first one's tone plays on" do
      let(:options) { { subtune: 2, seconds: 0.1 } }

      def sids = [0x42]

      it "plays the first SID on the left" do
        renderer.render(output("out.wav"))
        expect(steady_peak("out.wav", 0)).to be > 3000
      end

      it "plays the second SID on the right" do
        renderer.render(output("out.wav"))
        expect(steady_peak("out.wav", 1)).to be < 2000
      end
    end

    context "with an NTSC tune" do
      let(:options) { { subtune: 2, seconds: 0.5 } }

      def flags = 0x08

      # The triangle at $1121 runs at 257 Hz on a PAL clock and 267 Hz on an
      # NTSC one, 96 and 100 cycles over the steady 0.375 s.
      it "plays it at the NTSC clock's pitch" do
        renderer.render(output("out.wav"))
        expect(rising_crossings("out.wav")).to eq(100)
      end

      it "still writes as many samples as the length asks for" do
        renderer.render(output("out.wav"))
        expect(samples("out.wav").length).to eq(4000)
      end
    end
  end

  describe "#stream" do
    def frames
      list = []
      renderer.stream { |samples, rendered| list << [samples.size, rendered] }
      list
    end

    it "yields every frame's samples, the left and the right of each" do
      expect(frames.sum(&:first)).to eq(800)
    end

    context "when starting partway in" do
      before { renderer.from = 0.03 }

      it "yields the frames before it without their samples" do
        expect(frames.reject { |count, _| count.zero? }.map(&:last).min).to be > 0.03
      end

      it "still counts the seconds from the start" do
        expect(frames.first.last).to be < 0.03
      end
    end
  end
end
