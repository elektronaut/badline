# frozen_string_literal: true

require "spec_helper"
require "badline/chips/riot"
require_relative "../../../support/keyed_oracle"

describe Badline::Chips::RIOT::KeyedState do
  include KeyedOracle

  # RAM and ports written, the PA7 edge detector armed for rising edges,
  # and the timer two cycles into ÷8 with its interrupt enabled.
  def busy_riot
    Badline::Chips::RIOT.new.tap do |riot|
      riot.write_ram(0x10, 0xa5)
      [[0x01, 0x0f], [0x00, 0x05], [0x03, 0xf0], [0x02, 0x50], [0x07, 0], [0x1d, 3]].each do |reg, value|
        riot.poke(reg, value)
      end
      riot.pa7 = false
      2.times { riot.cycle! }
    end
  end

  def restored(riot)
    Badline::Chips::RIOT.new.tap { |fresh| keyed_round_trip(riot, fresh) }
  end

  # What a CPU and the peripheral see over the next 20 cycles.
  def outputs(riot)
    Array.new(20) do
      riot.cycle!
      [riot.port_a_output, riot.port_b_output, riot.timer.counter, riot.irq?, riot.read_ram(0x10)]
    end
  end

  it "saves again the fields it loaded" do
    riot = busy_riot
    expect(saved_fields(restored(riot))).to eq(saved_fields(riot))
  end

  it "runs on as the saved RIOT does" do
    riot = busy_riot
    copy = restored(riot)
    expect(outputs(copy)).to eq(outputs(riot))
  end

  it "sees the same PA7 edges as the saved RIOT" do
    riot = busy_riot
    copy = restored(riot)
    [riot, copy].each { |each_riot| each_riot.pa7 = true }
    expect(copy.peek(0x05)).to eq(riot.peek(0x05))
  end
end
