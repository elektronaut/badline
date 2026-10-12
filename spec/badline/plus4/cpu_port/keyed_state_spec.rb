# frozen_string_literal: true

require "spec_helper"
require "badline/plus4"
require_relative "../../../support/keyed_oracle"

# The port's keyed fields, loaded into a machine at power-on, which drives
# the serial bus and the tape's write line from them.
describe Badline::Plus4::CPUPort::KeyedState do
  include KeyedOracle

  let(:machine) { Badline::Plus4.new }
  let(:target) { Badline::Plus4.new }

  before do
    machine.port.poke(0, 0x0f)
    machine.port.poke(1, 0x05)
    keyed_round_trip(machine.port, target.port, "port.")
  end

  it "loads the registers" do
    expect([target.port.ddr, target.port.data]).to eq([0x0f, 0x05])
  end

  it "pulls the serial bus's lines the port drives" do
    expect(target.iec_bus.host_lines).to eq(machine.iec_bus.host_lines)
  end

  it "sets the tape's write line without recording an edge" do
    expect(target.datasette.instance_variable_get(:@write_high)).to be(false)
  end
end
