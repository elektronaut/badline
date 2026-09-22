# frozen_string_literal: true

require "spec_helper"

describe Badline::TimeOfDay do
  subject(:tod) { described_class.new(clock_hz: 50) }

  # One TOD pin pulse per cycle, divided by five into tenths.
  before do
    tod.fifty_hz = true
    tod.write(:tenths, 0x00, alarm: false)
  end

  def advance_tenths(count)
    (count * 5).times { tod.cycle! }
  end

  context "when first powered on" do
    let(:powered_on) { described_class.new(clock_hz: 50) }

    specify { expect(powered_on.hours).to eq(0x01) }
    specify { expect(powered_on.minutes).to eq(0x00) }
    specify { expect(powered_on.seconds).to eq(0x00) }
    specify { expect(powered_on.tenths).to eq(0x00) }

    it "leaves the clock stopped until the tenths are written" do
      10.times { powered_on.cycle! }
      expect(powered_on.tenths).to eq(0x00)
    end
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

  context "when the hour rolls past twelve" do
    before do
      tod.write_hours(0x12 | 0x80, alarm: false)
      tod.write(:minutes, 0x59, alarm: false)
      tod.write(:seconds, 0x59, alarm: false)
      tod.write(:tenths, 0x09, alarm: false)
      advance_tenths(1)
    end

    it "wraps to one without touching AM/PM" do
      expect(tod.hours).to eq(0x01)
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
      expect(tod.hours).to eq(0x01)
    end

    it "writes the alarm without changing the clock" do
      tod.write(:seconds, 0x30, alarm: true)
      expect(tod.seconds).to eq(0x00)
    end

    it "flips AM/PM when writing twelve o'clock" do
      tod.write_hours(0x12, alarm: false)
      expect(tod.hours).to eq(0x12 | 0x80)
    end

    it "flips AM/PM back when writing twelve PM" do
      tod.write_hours(0x12 | 0x80, alarm: false)
      expect(tod.hours).to eq(0x12)
    end

    it "does not flip AM/PM when writing the alarm hours" do
      tod.write_hours(0x12, alarm: true)
      tod.write_hours(0x12 | 0x80, alarm: false)
      expect(tod.hours).to eq(0x12)
    end
  end

  describe "out-of-range BCD" do
    it "keeps the written tenths until the next pulse" do
      tod.write(:tenths, 0x0f, alarm: false)
      expect(tod.tenths).to eq(0x0f)
    end

    it "counts the tenths on without carrying" do
      tod.write(:tenths, 0x0a, alarm: false)
      advance_tenths(1)
      expect(tod.tenths).to eq(0x0b)
    end

    it "wraps the tenths past fifteen without carrying" do
      tod.write(:seconds, 0x01, alarm: false)
      tod.write(:tenths, 0x0f, alarm: false)
      advance_tenths(1)
      expect(tod.seconds).to eq(0x01)
    end

    it "carries the seconds out of range on" do
      tod.write(:seconds, 0x69, alarm: false)
      tod.write(:tenths, 0x09, alarm: false)
      advance_tenths(1)
      expect(tod.seconds).to eq(0x70)
    end

    it "wraps the high second digit past seven without carrying" do
      tod.write(:minutes, 0x01, alarm: false)
      tod.write(:seconds, 0x79, alarm: false)
      tod.write(:tenths, 0x09, alarm: false)
      advance_tenths(1)
      expect(tod.minutes).to eq(0x01)
    end

    context "when the hour is out of range" do
      before do
        tod.write_hours(0x1a, alarm: false)
        tod.write(:minutes, 0x59, alarm: false)
        tod.write(:seconds, 0x59, alarm: false)
        tod.write(:tenths, 0x09, alarm: false)
        advance_tenths(1)
      end

      it "counts it on" do
        expect(tod.hours).to eq(0x1b)
      end
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

    it "keeps counting when the tenths are written while running" do
      3.times { tod.cycle! }
      tod.write(:tenths, 0x00, alarm: false)
      2.times { tod.cycle! }
      expect(tod.tenths).to eq(0x01)
    end

    it "restarts the count when the stopped clock is released" do
      3.times { tod.cycle! }
      tod.write_hours(0x01, alarm: false)
      tod.write(:tenths, 0x00, alarm: false)
      4.times { tod.cycle! }
      expect(tod.tenths).to eq(0x00)
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

    # The ring counter has six states but only compares on a pulse, so
    # dropping the divider below the count in flight costs a whole lap.
    context "when 50 Hz is selected mid-lap" do
      before do
        tod.fifty_hz = false
        5.times { tod.cycle! }
        tod.fifty_hz = true
      end

      it "does not tick before the counter comes round again" do
        5.times { tod.cycle! }
        expect(tod.tenths).to eq(0x00)
      end

      it "ticks eleven pulses after the restart" do
        6.times { tod.cycle! }
        expect(tod.tenths).to eq(0x01)
      end
    end
  end

  describe "the alarm" do
    before do
      tod.write(:tenths, 0x01, alarm: true)
      tod.write(:seconds, 0x00, alarm: true)
      tod.write(:minutes, 0x00, alarm: true)
      tod.write_hours(0x01, alarm: true)
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

    it "yields when a write brings the clock onto the alarm time" do
      fired = false
      tod.write(:tenths, 0x01, alarm: false)
      tod.cycle! { fired = true }
      expect(fired).to be(true)
    end

    it "yields when a write brings the alarm onto the clock time" do
      fired = false
      tod.write(:tenths, 0x00, alarm: true)
      tod.cycle! { fired = true }
      expect(fired).to be(true)
    end

    context "when a write leaves the registers unchanged" do
      before do
        tod.write(:tenths, 0x01, alarm: false)
        tod.cycle!
      end

      it "does not yield again" do
        fired = false
        tod.write(:tenths, 0x01, alarm: false)
        tod.cycle! { fired = true }
        expect(fired).to be(false)
      end
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
