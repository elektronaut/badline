# frozen_string_literal: true

require "spec_helper"
require "badline/ffi"
require "badline/frontend"

describe Badline::Frontend::KIM1Panel do
  subject(:picture) { described_class.new }

  # A KIM-1 as #follow reads it: its cycle count, the lit cycles of each
  # segment, the key held and the SST switch.
  let(:computer) { Struct.new(:cycles, :panel, :sst).new(0, panel, false) }
  let(:panel) { Struct.new(:lit_cycles, :held).new(Array.new(42, 0), nil) }

  # Runs `frames` frames of `cycles` each with digit 0's segment a lit
  # for `share` of the time.
  def lit_for(share, frames: 1, cycles: 16_640)
    frames.times do
      computer.cycles += cycles
      panel.lit_cycles = [(cycles * share).to_i] + Array.new(41, 0)
      picture.follow(computer)
    end
    picture.brightness.first
  end

  before { picture.follow(computer) }

  it "fills a window as wide and high as a PAL C64's crop" do
    expect([picture.width, picture.height]).to eq([Badline::Frontend::Screen::MIN_WIDTH, 272])
  end

  describe "#key_at" do
    it "finds the keys where they are drawn" do
      expect([picture.key_at(30, 105), picture.key_at(80, 220), picture.key_at(165, 110)]).to eq(%w[GO 5 SST])
    end

    it "finds nothing in the gaps and past the keypad" do
      expect([picture.key_at(66, 105), picture.key_at(30, 124), picture.key_at(300, 105)]).to eq(["", "", ""])
    end
  end

  describe "the digits" do
    it "light fully at the monitor's share of the time, once settled" do
      expect(lit_for(0.16, frames: 30)).to be_within(0.01).of(1.0)
    end

    it "light dimmer for a program that scans slower" do
      expect(lit_for(0.04, frames: 30)).to be_within(0.01).of(Math.sqrt(0.04 / 0.15))
    end

    it "follow a change over some frames, not at once" do
      expect(lit_for(0.16)).to be_between(0.2, 0.5)
    end

    it "stay as they are while no cycles run" do
      lit_for(0.16)
      expect { picture.follow(computer) }.not_to(change(picture, :brightness))
    end
  end

  it "draws the key held in another shade" do
    panel.held = "GO"
    picture.clear_dirty_lines!
    picture.follow(computer)
    expect(picture.display[(105 * 384) + 26]).to eq(described_class::KEY_HELD)
  end
end
