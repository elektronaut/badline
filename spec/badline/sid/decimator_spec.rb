# frozen_string_literal: true

require "spec_helper"

describe Badline::SID::Decimator do
  subject(:decimator) { described_class.new(clock_hz: 100, rate: 10) }

  def push(values)
    values.filter_map { |value| decimator.push(value) }
  end

  describe "#push" do
    it "holds back until a window closes" do
      expect(decimator.push(1000)).to be_nil
    end

    it "emits one sample per window" do
      expect(push([1000] * 30).length).to eq(3)
    end

    it "averages the window" do
      expect(push([1000] * 10)).to eq([1000])
    end

    it "averages away what point sampling would keep" do
      expect(push(Array.new(10) { |i| i.even? ? 1000 : -1000 })).to eq([0])
    end

    it "rounds to the nearest integer" do
      expect(push(([1] * 9) + [2])).to eq([1])
    end

    it "weighs a sample by the cycles it stands for" do
      decimator.push(1000, 9)
      expect(decimator.push(0, 1)).to eq(900)
    end
  end

  describe "#cycles_to_close" do
    it "spans a whole window at the start" do
      expect(decimator.cycles_to_close).to eq(10)
    end

    it "counts down as cycles are pushed" do
      decimator.push(0, 3)
      expect(decimator.cycles_to_close).to eq(7)
    end

    context "with the PAL clock and CD rate" do
      subject(:decimator) do
        described_class.new(clock_hz: Badline::TimeOfDay::CLOCK_HZ, rate: 44_100)
      end

      it "emits the output rate over a second of cycles" do
        expect(push([0] * Badline::TimeOfDay::CLOCK_HZ).length).to eq(44_100)
      end
    end
  end
end
