# frozen_string_literal: true

require "spec_helper"

describe Badline::TimeOfDay do
  subject(:tod) { described_class.new(clock_hz: 50) }

  # One TOD pin pulse per cycle, divided by five into tenths.
  before { tod.fifty_hz = true }

  def advance_tenths(count)
    (count * 5).times { tod.cycle! }
  end

  context "when first powered on" do
    specify { expect(tod.hours).to eq(0x12) }
    specify { expect(tod.minutes).to eq(0x00) }
    specify { expect(tod.seconds).to eq(0x00) }
    specify { expect(tod.tenths).to eq(0x00) }
  end

  it "advances tenths from the cycle clock" do
    advance_tenths(3)
    expect(tod.tenths).to eq(0x03)
  end

  context "when the tenths roll over" do
    before { advance_tenths(10) }

    specify { expect(tod.seconds).to eq(0x01) }
    specify { expect(tod.tenths).to eq(0x00) }
  end

  context "when the seconds roll over" do
    before do
      tod.write(:seconds, 0x59, alarm: false)
      tod.write(:tenths, 0x09, alarm: false)
      advance_tenths(1)
    end

    specify { expect(tod.minutes).to eq(0x01) }
    specify { expect(tod.seconds).to eq(0x00) }
  end

  context "when the hour rolls over" do
    before do
      tod.write_hours(0x11, alarm: false)
      tod.write(:minutes, 0x59, alarm: false)
      tod.write(:seconds, 0x59, alarm: false)
      tod.write(:tenths, 0x09, alarm: false)
      advance_tenths(1)
    end

    it "advances the hour and toggles AM/PM" do
      expect(tod.hours).to eq(0x12 | 0x80)
    end
  end

  it "latches the registers when the hours are read" do
    tod.hours
    advance_tenths(10)
    expect(tod.seconds).to eq(0x00)
  end

  it "releases the latch when the tenths are read" do
    tod.hours
    advance_tenths(10)
    tod.tenths
    expect(tod.seconds).to eq(0x01)
  end

  describe "setting" do
    it "sets the hours with the AM/PM bit" do
      tod.write_hours(0x11 | 0x80, alarm: false)
      expect(tod.hours).to eq(0x11 | 0x80)
    end

    it "sets the minutes" do
      tod.write(:minutes, 0x24, alarm: false)
      expect(tod.minutes).to eq(0x24)
    end

    it "does not let setting one register affect the others" do
      tod.write(:minutes, 0x24, alarm: false)
      expect(tod.hours).to eq(0x12)
    end

    it "writes the alarm without changing the clock" do
      tod.write(:seconds, 0x30, alarm: true)
      expect(tod.seconds).to eq(0x00)
    end
  end

  describe "the tenth-of-a-second divider" do
    it "does not tick before five TOD pin pulses" do
      4.times { tod.cycle! }
      expect(tod.tenths).to eq(0x00)
    end

    it "ticks on the fifth pulse" do
      5.times { tod.cycle! }
      expect(tod.tenths).to eq(0x01)
    end

    context "when 60 Hz is selected" do
      before { tod.fifty_hz = false }

      it "does not tick on the fifth pulse" do
        5.times { tod.cycle! }
        expect(tod.tenths).to eq(0x00)
      end

      it "ticks on the sixth pulse" do
        6.times { tod.cycle! }
        expect(tod.tenths).to eq(0x01)
      end
    end
  end

  describe "the alarm" do
    before do
      tod.write_hours(0x12, alarm: true)
      tod.write(:minutes, 0x00, alarm: true)
      tod.write(:seconds, 0x00, alarm: true)
      tod.write(:tenths, 0x01, alarm: true)
    end

    it "yields when the clock reaches the alarm time" do
      fired = false
      5.times { tod.cycle! { fired = true } }
      expect(fired).to be(true)
    end

    it "does not yield before the clock matches" do
      fired = false
      4.times { tod.cycle! { fired = true } }
      expect(fired).to be(false)
    end
  end

  describe "the write stall" do
    it "halts the clock when the hours are written" do
      tod.write_hours(0x12, alarm: false)
      advance_tenths(2)
      expect(tod.tenths).to eq(0x00)
    end

    it "resumes the clock when the tenths are written" do
      tod.write_hours(0x12, alarm: false)
      tod.write(:tenths, 0x00, alarm: false)
      advance_tenths(1)
      expect(tod.tenths).to eq(0x01)
    end

    it "is not triggered by writing the alarm hours" do
      tod.write_hours(0x12, alarm: true)
      advance_tenths(1)
      expect(tod.tenths).to eq(0x01)
    end
  end
end
