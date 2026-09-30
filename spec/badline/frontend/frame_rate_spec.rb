# frozen_string_literal: true

require "spec_helper"
require "badline/ffi"
require "badline/frontend"

describe Badline::Frontend::FrameRate do
  let(:pal_clock_hz) { Badline::Region::PAL.clock_hz }

  describe ".machine" do
    it "clocks a PAL frame of 312 lines of 63 cycles at the PAL clock" do
      rate = described_class.machine(Badline::Region::PAL)
      expect([rate.base_cycles, rate.seconds]).to eq([19_656, 19_656 / 985_248.0])
    end

    it "clocks an NTSC frame of 263 lines of 65 cycles at the NTSC clock" do
      rate = described_class.machine(Badline::Region::NTSC)
      expect([rate.base_cycles, rate.seconds]).to eq([17_095, 17_095 / 1_022_727.0])
    end
  end

  describe ".display" do
    it "clocks as many cycles as the machine runs in one refresh" do
      expect(described_class.display(60, pal_clock_hz).base_cycles).to eq(16_420)
    end

    it "lasts one refresh" do
      expect(described_class.display(60, pal_clock_hz).seconds).to be_within(1e-6).of(1.0 / 60)
    end

    it "clocks fewer cycles on a faster display" do
      expect(described_class.display(144, pal_clock_hz).base_cycles).to eq(6842)
    end

    it "clocks at the machine's clock" do
      expect(described_class.display(60, 1_022_727).base_cycles).to eq(17_045)
    end

    it "takes a display that reports no rate for 60 Hz" do
      expect(described_class.display(0, pal_clock_hz).refresh).to eq(60)
    end
  end

  describe "#cycles" do
    subject(:rate) { described_class.display(50, pal_clock_hz) }

    let(:base) { rate.base_cycles }

    it "clocks the base cycles with the audio queue on target" do
      expect(rate.cycles(0.08, 0.08)).to eq(base)
    end

    it "clocks more cycles as the queue runs low" do
      expect(rate.cycles(0.04, 0.08)).to eq((base * (1 + (0.5 * 0.0001) + (0.5 * 0.02))).round)
    end

    it "clocks fewer cycles as the queue fills" do
      expect(rate.cycles(0.12, 0.08)).to be < base
    end

    it "builds up a trim while the queue stays low" do
      100.times { rate.cycles(0.04, 0.08) }
      expect(rate.trim).to be_within(1e-9).of(100 * 0.5 * 0.0001)
    end

    it "keeps the trim when the queue is back on target" do
      100.times { rate.cycles(0.04, 0.08) }
      expect(rate.cycles(0.08, 0.08)).to eq((base * (1 + rate.trim)).round)
    end

    it "trims by no more than MAX_TRIM and PROPORTIONAL together" do
      10_000.times { rate.cycles(0.0, 0.08) }
      expect(rate.cycles(0.0, 0.08)).to eq((base * 1.07).round)
    end
  end

  describe "#refit" do
    subject(:rate) { described_class.display(60, pal_clock_hz) }

    it "sizes the frames to the rate measured" do
      rate.refit(625, 10.0)
      expect([rate.base_cycles, rate.seconds]).to eq([15_764, 15_764 / 985_248.0])
    end

    it "keeps the reported rate when the measure is far off it" do
      rate.refit(300, 10.0)
      expect(rate.base_cycles).to eq(16_420)
    end

    it "ignores an empty measure" do
      rate.refit(0, 0.0)
      expect(rate.base_cycles).to eq(16_420)
    end
  end

  describe "#vsync_holds?" do
    subject(:rate) { described_class.display(60, pal_clock_hz) }

    it "holds while frames come at the display's rate" do
      expect(rate.vsync_holds?(50, 50 / 60.0)).to be(true)
    end

    it "holds while frames come slower than the display" do
      expect(rate.vsync_holds?(50, 2.0)).to be(true)
    end

    it "doesn't hold when frames come far faster than the display" do
      expect(rate.vsync_holds?(50, 0.2)).to be(false)
    end
  end
end
