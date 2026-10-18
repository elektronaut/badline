# frozen_string_literal: true

require "spec_helper"
require "badline/chips/riot"
require_relative "../../../../support/keyed_oracle"

describe Badline::Chips::RIOT::Timer::FastForward do
  include KeyedOracle

  # A timer loaded with +value+ at the interval, run +before+ cycles one by
  # one.
  def timer(value, interval, before, irq: true)
    Badline::Chips::RIOT::Timer.new.tap do |timer|
      timer.write(value, interval, irq)
      before.times { timer.cycle! }
    end
  end

  # [value, interval, cycles before, cycles at once]
  cases = [[52, 1, 0, 415], [52, 1, 0, 416], [52, 1, 3, 600], [0, 2, 0, 1], [1, 3, 1000, 2000],
           [255, 0, 0, 255], [255, 0, 0, 256], [3, 0, 10, 513], [9, 2, 70, 1], [200, 3, 5, 100_000]]

  cases.each do |value, interval, before, cycles|
    it "runs #{cycles} cycles of #{value} at interval #{interval}, #{before} in, as cycle! does" do
      fast = timer(value, interval, before)
      slow = timer(value, interval, before)
      fast.fast_forward(cycles)
      cycles.times { slow.cycle! }
      expect(saved_fields(fast, "t.")).to eq(saved_fields(slow, "t."))
    end
  end

  it "stays quiet until the cycle before the flag" do
    expect(timer(52, 1, 0).quiet_cycles).to eq(415)
  end

  it "stays quiet the counter's worth of cycles once expired" do
    expect(timer(1, 0, 3).quiet_cycles).to eq(0xfd)
  end

  it "stays quiet for ever with its interrupt off" do
    expect(timer(1, 0, 0, irq: false).quiet_cycles).to eq(described_class::QUIET)
  end
end
