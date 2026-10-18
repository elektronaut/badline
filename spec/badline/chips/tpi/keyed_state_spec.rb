# frozen_string_literal: true

require "spec_helper"
require "badline/chips/tpi"
require_relative "../../../support/keyed_oracle"

describe Badline::Chips::TPI::KeyedState do
  include KeyedOracle

  def tpi = Badline::Chips::TPI.new

  # A TPI in mode 1 with priority, I1's interrupt in service on the stack
  # and I0 latched behind it, CA and CB high.
  def servicing
    tpi.tap do |unit|
      unit.poke(6, 0xf3)
      unit.poke(5, 0x1f)
      unit.poke(3, 0x3f)
      [1, 0].each do |index|
        unit.interrupt_line(index, false)
        unit.interrupt_line(index, true)
        unit.peek(7) if index == 1
      end
    end
  end

  it "saves again what it loaded" do
    saved = servicing
    keyed_round_trip(saved, target = tpi)
    expect(saved_fields(target)).to eq(saved_fields(saved))
  end

  it "loads the latches, the stack and CA" do
    keyed_round_trip(servicing, target = tpi)
    expect([target.latches, target.stack, target.ca?, target.irq?]).to eq([0x01, [0x02], true, false])
  end

  it "lets the loaded stack hold the lower interrupt off until the AIR is written" do
    keyed_round_trip(servicing, target = tpi)
    target.poke(7, 0)
    expect(target.peek(7)).to eq(0x01)
  end
end
