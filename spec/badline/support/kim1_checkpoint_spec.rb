# frozen_string_literal: true

require "spec_helper"
require "badline/support/kim1_checkpoint"

describe Badline::Support::KIM1Checkpoint do
  let(:machine) { Badline::KIM1.new }
  let(:before) { described_class.take(machine) }

  def changed_by
    before
    yield
    described_class.take(machine).differences(before)
  end

  it "gives two fresh machines the same digests" do
    expect(described_class.take(Badline::KIM1.new)).to eq(before)
  end

  it "notices a RAM write in the RAM alone" do
    expect(changed_by { machine.poke(0x0123, 0x55) }).to eq(["ram"])
  end

  it "notices U3's RAM in U3 alone" do
    expect(changed_by { machine.poke(0x1780, 0x55) }).to eq(["u3"])
  end

  it "notices U2's timer in U2 alone" do
    expect(changed_by { machine.poke(0x1747, 0x10) }).to eq(["u2"])
  end

  it "notices a key held down" do
    expect(changed_by { machine.press_key("GO") }).to eq(["panel"])
  end

  it "reads back what #to_s writes" do
    expect(described_class.parse(before.to_s)).to eq(before)
  end
end
