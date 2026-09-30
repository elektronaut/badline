# frozen_string_literal: true

require "spec_helper"
require_relative "../support/snapshot_scenarios"

describe Badline::SID, "#save_state" do
  include SnapshotScenarios

  def settled(sid)
    sid.voices
    sid
  end

  %i[mos6581 mos8580].each do |model|
    context "with the #{model}" do
      let(:saved) { run(demo_machine(sid_model: model), 30_001).sid }
      let(:target) { run(demo_machine(sid_model: model), 11_111).sid }

      it "restores the registers, voices, filter and the span not caught up" do
        round_trip(saved, target)
        expect(state_differences(saved, target)).to be_empty
      end

      it "catches up as the saved SID does" do
        round_trip(saved, target)
        [saved, target].each { |sid| 5000.times { sid.cycle! } }
        expect(state_differences(settled(saved), settled(target))).to be_empty
      end
    end
  end

  context "with writes queued" do
    let(:saved) do
      described_class.new.tap do |sid|
        sid.synthesize!
        [[0xd400, 0x31], [0xd401, 0x1c], [0xd405, 0x09], [0xd418, 0x1f], [0xd404, 0x41]].each do |addr, value|
          7.times { sid.cycle! }
          sid.poke(addr, value)
        end
      end
    end

    it "keeps the queue and plays it out as the saved SID does" do
      target = described_class.new
      target.synthesize!
      round_trip(saved, target)
      expect(settled(target).output).to eq(settled(saved).output)
    end

    it "leaves a target that doesn't synthesize not synthesizing" do
      expect(round_trip(saved, described_class.new)).not_to be_synthesizing
    end
  end
end
