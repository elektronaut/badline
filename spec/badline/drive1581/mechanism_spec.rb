# frozen_string_literal: true

require "spec_helper"

describe Badline::Drive1581::Mechanism do
  subject(:mechanism) { described_class.new }

  let(:disk) { Badline::Drive1581::Disk.new }
  let(:revolution) { described_class::REVOLUTION }

  def spin
    mechanism.insert(disk, 0)
    mechanism.motor(true, 0)
  end

  it "turns a disk while the motor runs" do
    spin
    expect(mechanism.angle(revolution + 5)).to eq(5)
  end

  it "holds the disk still with the motor off" do
    spin
    mechanism.motor(false, 100)
    expect(mechanism.angle(revolution)).to eq(100)
  end

  it "pulses the index sensor at the start of each turn" do
    spin
    expect(mechanism.index?(revolution + 10)).to be(true)
  end

  it "leaves the index sensor dark through the rest of the turn" do
    spin
    expect(mechanism.index?(revolution / 2)).to be(false)
  end

  it "is ready only with a disk turning" do
    mechanism.motor(true, 0)
    expect(mechanism.ready?).to be(false)
  end

  it "reports the disk changed until a step with a disk in" do
    mechanism.insert(disk, 0)
    mechanism.step(true)
    expect(mechanism.disk_changed?).to be(false)
  end

  it "reports the disk changed again once it comes out" do
    mechanism.insert(disk, 0)
    mechanism.step(true)
    mechanism.insert(nil, 0)
    expect(mechanism.disk_changed?).to be(true)
  end

  it "stops the head at cylinder 0" do
    mechanism.step(false)
    expect(mechanism.track0?).to be(true)
  end

  it "reports write protection without a disk" do
    expect(mechanism.write_protected?).to be(true)
  end

  it "finds the track under the head on the side selected" do
    disk.write(2, 1, Badline::Drive1581::Track.new([]))
    mechanism.insert(disk, 0)
    2.times { mechanism.step(true) }
    mechanism.side = 1
    expect(mechanism.track).to equal(disk.track(2, 1))
  end
end
