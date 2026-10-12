# frozen_string_literal: true

require "spec_helper"
require "badline/plus4"
require_relative "../../../support/keyed_oracle"

describe Badline::Plus4::ACIA::KeyedState do
  include KeyedOracle

  it "loads the command and control registers" do
    saved, target = Array.new(2) { Badline::Plus4::ACIA.new }
    saved.poke(0xfd02, 0x0b)
    saved.poke(0xfd03, 0x1e)
    keyed_round_trip(saved, target)
    expect([target.command, target.control]).to eq([0x0b, 0x1e])
  end
end
