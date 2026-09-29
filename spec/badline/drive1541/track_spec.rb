# frozen_string_literal: true

require "spec_helper"

describe Badline::Drive1541::Track do
  let(:turn) { described_class::TURN }
  let(:tick) { described_class::TICK }

  # Pinned by drive/rpm: every track takes one turn, 200 ms.
  describe "#cell_at" do
    it "starts the first byte's top bit at the index angle" do
      track = described_class.new([0x55] * 7692, 3)
      expect(track.cell_at(0)).to eq([0, 0x80, turn / (7692 * 8)])
    end

    it "passes a track as long as a turn holds at its zone's rate at that rate" do
      expect(described_class.new([0x55] * 7142, 2).width / tick).to eq(56)
    end

    it "spreads a longer track over the turn" do
      expect(described_class.new([0x55] * 7821, 3).width * 7821 * 8).to be_within(7821 * 8).of(turn)
    end

    it "ends the last cell at the end of the turn" do
      track = described_class.new([0x55] * 6250, 0)
      expect(track.cell_at(turn - 1)).to eq([6249, 0x01, turn])
    end

    it "widens a speed map's cells in slower zones" do
      track = described_class.new([0x55] * 4, 3, [3, 3, 1, 1])
      expect(track.widths.map { |width| width * 8 * 28 / turn }).to eq([6, 6, 7, 7])
    end

    it "finds the cell under a speed-mapped track's head" do
      track = described_class.new([0x55] * 4, 3, [3, 3, 1, 1])
      expect(track.cell_at(track.widths[0] * 17).first(2)).to eq([2, 0x80])
    end
  end

  describe "#relaid" do
    let(:track) { described_class.new(([0xff] * 3846) + ([0x00] * 3846), 3) }

    it "lays the track out as a turn at the zone's rate" do
      expect([track.relaid(1).length, track.relaid(1).zone]).to eq([6666, 1])
    end

    it "keeps each flux transition at its angle" do
      expect(track.relaid(0).bytes.values_at(0, 3120, 3130, 6249)).to eq([0xff, 0xff, 0x00, 0x00])
    end
  end

  it "is written at a zone when all of it is" do
    expect([described_class.new([0], 2).written_at?(2), described_class.new([0], 2, [2]).written_at?(2)])
      .to eq([true, false])
  end
end
