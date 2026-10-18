# frozen_string_literal: true

require "spec_helper"
require "badline/chips/rriot"
require_relative "../../../support/keyed_oracle"

describe Badline::Chips::RRIOT::KeyedState do
  include KeyedOracle

  let(:rom) { Array.new(1024, 0xea) }

  # RAM and ports written, and the timer two cycles into ÷8 with its
  # interrupt enabled.
  def busy_rriot
    Badline::Chips::RRIOT.new(rom:).tap do |rriot|
      rriot.write_ram(0x10, 0xa5)
      [[0x01, 0x0f], [0x00, 0x05], [0x03, 0x70], [0x02, 0x50], [0x0d, 3]].each { |reg, value| rriot.poke(reg, value) }
      2.times { rriot.cycle! }
    end
  end

  def restored(rriot)
    Badline::Chips::RRIOT.new(rom:).tap { |fresh| keyed_round_trip(rriot, fresh) }
  end

  # What a CPU and the peripheral see over the next 30 cycles.
  def outputs(rriot)
    Array.new(30) do
      rriot.cycle!
      [rriot.port_a_output, rriot.port_b_output, rriot.timer.counter, rriot.irq?, rriot.read_ram(0x10)]
    end
  end

  it "saves again the fields it loaded" do
    rriot = busy_rriot
    expect(saved_fields(restored(rriot))).to eq(saved_fields(rriot))
  end

  it "runs on as the saved RRIOT does" do
    rriot = busy_rriot
    copy = restored(rriot)
    expect(outputs(copy)).to eq(outputs(rriot))
  end
end
