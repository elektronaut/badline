# frozen_string_literal: true

require "spec_helper"

describe Badline::Status do
  subject(:value) { status.value }

  let(:status) { described_class.new(flags) }
  let(:flags) { [:carry, :zero, nil, :decimal, 0] }

  it { is_expected.to eq(0x0) }

  it "has setter methods" do
    status.carry = true
    status.decimal = true
    expect(status.value).to eq(0x09)
  end

  it "has boolean methods" do
    status.decimal = true
    expect(status.decimal?).to be(true)
  end

  it "has accessor methods" do
    status.decimal = true
    expect(status.decimal).to be(1)
  end

  it "reads a flag by name" do
    status.set(:decimal, true)
    expect(status.set?(:decimal)).to be(true)
  end

  it "reads a flag bit by name" do
    status.set(:decimal, true)
    expect(status.bit(:decimal)).to be(1)
  end

  it "raises for a flag this instance does not carry" do
    expect { status.overflow? }
      .to raise_error(NoMethodError, /undefined flag overflow/)
  end

  describe ".bitmask" do
    subject { status.bitmask }

    it { is_expected.to eq(0b00001011) }
  end

  context "when flag is always 1" do
    let(:flags) { [:carry, :zero, 1, :decimal, 1, nil, 0] }

    before { status.value = 0x0 }

    it { is_expected.to eq(0b00010100) }

    specify { expect(status.high_mask).to eq(0b00010100) }
  end

  context "when flag is always 0" do
    let(:flags) { [:carry, :zero, 0, :decimal, 0, nil, 1] }

    before { status.value = 0xff }

    it { is_expected.to eq(0b11101011) }

    specify { expect(status.low_mask).to eq(0b00010100) }
  end
end
