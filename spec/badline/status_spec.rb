# frozen_string_literal: true

require "spec_helper"

describe Badline::Status do
  subject(:value) { status.value }

  let(:status) { described_class.new(flags) }
  let(:flags) { [:foo, :bar, nil, :baz, 0] }

  it { is_expected.to eq(0x0) }

  describe ".bitmask" do
    subject { status.bitmask }

    it { is_expected.to eq(0b00001011) }
  end

  context "when flag is always 1" do
    let(:flags) { [:a, :b, 1, :c, 1, nil, 0] }

    before { status.value = 0x0 }

    it { is_expected.to eq(0b00010100) }

    specify { expect(status.high_mask).to eq(0b00010100) }
  end

  context "when flag is always 0" do
    let(:flags) { [:a, :b, 0, :c, 0, nil, 1] }

    before { status.value = 0xff }

    it { is_expected.to eq(0b11101011) }

    specify { expect(status.low_mask).to eq(0b00010100) }
  end

  describe Badline::CPUStatus do
    let(:status) { described_class.new(Badline::CPU::STATUS_FLAGS) }

    it "has setter methods" do
      status.carry = true
      status.negative = 1
      expect(status.value).to eq(0xa1)
    end

    it "has boolean methods" do
      status.zero = true
      expect(status.zero?).to be(true)
    end

    it "has accessor methods" do
      status.overflow = true
      expect(status.overflow).to be(1)
    end

    it "clears a flag set to 0" do
      status.value = 0xff
      status.decimal = 0
      expect(status.value).to eq(0xf7)
    end
  end

  describe Badline::ControlRegister do
    let(:status) { described_class.new(%i[start output out_mode run_mode load in_cnt in_timer_a alarm]) }

    it "maps the CRB bits" do
      status.alarm = true
      status.in_timer_a = true
      expect(status.value).to eq(0xc0)
    end

    it "maps the CRA bits" do
      status.clock_frequency = true
      status.serial_mode = true
      expect(status.value).to eq(0xc0)
    end
  end
end
