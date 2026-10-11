# frozen_string_literal: true

require "spec_helper"
require_relative "../../../support/keyed_oracle"
require_relative "../../../support/z80_bus"

# The Z80's keyed fields against its positional save_state, between
# instructions.
describe Badline::Chips::Z80::KeyedState do
  include KeyedOracle

  let(:bus) { Z80Bus.new }
  # Loads the alternate registers, IX and IY, enables interrupts in mode 2
  # and halts, with the NMI line raised.
  let(:cpu) do
    bus.load(0, 0x31, 0x00, 0x80, 0x21, 0x34, 0x12, 0xd9, 0x08, 0xdd, 0x21, 0x78, 0x56, 0xfd, 0x21, 0xbc, 0x9a,
             0xed, 0x5e, 0xfb, 0x76)
    Badline::Chips::Z80.new(bus).tap do |z80|
      9.times { z80.step! }
      z80.nmi = true
    end
  end
  let(:fresh) { Badline::Chips::Z80.new(Z80Bus.new) }

  it "restores the positional state" do
    keyed_round_trip(cpu, fresh)
    expect(positional(fresh)).to eq(positional(cpu))
  end

  it "reads every field it writes" do
    expect(keyed_round_trip(cpu, fresh).report.lines(verbose: true)).to be_empty
  end

  it "was saved halted in interrupt mode 2 with an NMI pending" do
    expect(%i[@halted @im @nmi_pending].map { |name| cpu.instance_variable_get(name) }).to eq([true, 2, true])
  end
end
