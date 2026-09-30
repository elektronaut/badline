# frozen_string_literal: true

require "spec_helper"
require_relative "../support/snapshot_scenarios"

describe Badline::VIA, "#save_state" do
  include SnapshotScenarios

  # Both timers running, timer 1 free-running with PB7 on, the shift
  # register clocking out off φ2, CA2 pulsing and a flag raised.
  let(:via) do
    described_class.new(start: 0x1800).tap do |via|
      { 0x02 => 0xff, 0x00 => 0x5a, 0x0b => 0xd8, 0x0c => 0x0a, 0x0e => 0xc0, 0x04 => 0x34, 0x05 => 0x12,
        0x08 => 0x40, 0x09 => 0x00, 0x0a => 0xa5, 0x01 => 0x77 }.each { |reg, value| via.poke(0x1800 + reg, value) }
      via.ca1 = false
      37.times { via.cycle! }
    end
  end
  let(:target) { described_class.new(start: 0x1800) }

  it "restores every register, timer, line and flag" do
    expect(state_differences(via, round_trip(via, target))).to be_empty
  end

  it "counts on as the saved VIA does" do
    round_trip(via, target)
    500.times { [via, target].each(&:cycle!) }
    expect(state_differences(via, target)).to be_empty
  end
end
