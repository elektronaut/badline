# frozen_string_literal: true

require "spec_helper"
require "badline/plus4"
require_relative "../../../support/keyed_oracle"

describe Badline::Plus4::UserPort::KeyedState do
  include KeyedOracle

  it "loads the 6529's latch" do
    saved, target = Array.new(2) { Badline::Plus4::UserPort.new(Badline::Drives::Datasette.new(level: true)) }
    saved.poke(0xfd10, 0x3c)
    keyed_round_trip(saved, target)
    expect(target.output).to eq(0x3c)
  end
end
