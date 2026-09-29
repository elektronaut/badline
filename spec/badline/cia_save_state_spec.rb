# frozen_string_literal: true

require "spec_helper"
require_relative "../support/snapshot_scenarios"

describe Badline::CIA, "#save_state" do
  include SnapshotScenarios

  def run_chip(cia, cycles)
    cycles.times { cia.cycle! }
    cia
  end

  def restored(source, target)
    round_trip(source, target)
    state_differences(source, target)
  end

  %i[mos6526 mos6526a].each do |model|
    context "with the #{model}" do
      let(:saved) { run(demo_machine(cia_model: model), 30_001) }
      let(:target) { run(demo_machine(cia_model: model), 12_345) }

      it "restores CIA 1 as it was saved" do
        expect(restored(saved.cia1, target.cia1)).to be_empty
      end

      it "restores CIA 2, with its timer running" do
        expect(restored(saved.cia2, target.cia2)).to be_empty
      end

      it "runs on as the saved chip does" do
        round_trip(saved.cia2, target.cia2)
        run_chip(saved.cia2, 70_000)
        run_chip(target.cia2, 70_000)
        expect(state_differences(saved.cia2, target.cia2)).to be_empty
      end
    end
  end

  context "with the TOD clock latched and an alarm set" do
    let(:saved) do
      described_class.new(start: 0xdc00).tap do |cia|
        cia.poke(0xdc0b, 0x11)
        cia.poke(0xdc08, 0x03)
        cia.poke(0xdc0f, 0x80)
        cia.poke(0xdc0a, 0x42)
        cia.poke(0xdc0f, 0x00)
        run_chip(cia, 150_001)
        cia.peek(0xdc0b)
      end
    end

    it "restores the clock, the alarm and the latch" do
      expect(restored(saved, described_class.new(start: 0xdc00))).to be_empty
    end
  end

  context "with a byte half shifted out" do
    let(:saved) do
      described_class.new(start: 0xdc00).tap do |cia|
        cia.poke(0xdc04, 0x03)
        cia.poke(0xdc05, 0x00)
        cia.poke(0xdc0e, 0x51)
        cia.poke(0xdc0c, 0xa5)
        run_chip(cia, 37)
      end
    end

    it "restores the shift register mid-byte" do
      target = described_class.new(start: 0xdc00)
      round_trip(saved, target)
      run_chip(saved, 100)
      run_chip(target, 100)
      expect(state_differences(saved, target)).to be_empty
    end
  end
end
