# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/snapshot_scenarios"

describe Badline::CIA, "#fast_forward" do
  include SnapshotScenarios

  # The 1571 DOS's setup: interrupts masked, timer B stopped, and timer A
  # counting ø2 in continuous mode from +latch+, with the serial port an
  # input.
  def free_running(latch, settle)
    described_class.new(start: 0x4000).tap do |cia|
      cia.poke(0x400d, 0x7f)
      cia.poke(0x400f, 0x08)
      cia.poke(0x4004, latch)
      cia.poke(0x4005, 0x00)
      cia.poke(0x400e, 0x11)
      settle.times { cia.cycle! }
    end
  end

  def stepped(cia, cycles)
    cycles.times { cia.cycle! }
    cia
  end

  def skipped(cia, cycles)
    cia.fast_forward(cycles) if cia.quiet?
    cia
  end

  [[6, 9, 1], [6, 13, 6], [6, 20, 7], [6, 20, 701], [2, 8, 3], [255, 300, 1000]].each do |latch, settle, cycles|
    it "lands where #{cycles} cycles take a timer A from #{latch} after #{settle}" do
      expect(state_differences(stepped(free_running(latch, settle), cycles),
                               skipped(free_running(latch, settle), cycles))).to be_empty
    end
  end

  it "counts a free-running timer A as quiet" do
    expect(free_running(6, 20)).to be_quiet
  end

  it "leaves a timer A it would interrupt for to run cycle by cycle" do
    cia = free_running(6, 20)
    cia.poke(0x400d, 0x81)
    expect(cia).not_to be_quiet
  end

  # Timer A started with CRA +control+ from +latch+, timer B stopped and
  # interrupts masked.
  def started(control, latch = 6)
    described_class.new(start: 0x4000).tap do |cia|
      cia.poke(0x400d, 0x7f)
      cia.poke(0x4004, latch & 0xff)
      cia.poke(0x4005, latch >> 8)
      cia.poke(0x400e, control)
      20.times { cia.cycle! }
    end
  end

  { "in one-shot mode" => 0x19, "counting CNT" => 0x31, "driving the serial port" => 0x51 }.each do |mode, control|
    it "leaves a timer A #{mode} to run cycle by cycle" do
      expect(started(control, 0x1006)).not_to be_quiet
    end
  end

  it "leaves timer B counting to run cycle by cycle" do
    cia = free_running(6, 20)
    cia.poke(0x400f, 0x01)
    expect(cia).not_to be_quiet
  end

  it "lands where stepping does for a timer A whose PB6 output toggles" do
    expect(state_differences(stepped(started(0x17), 1_001), skipped(started(0x17), 1_001))).to be_empty
  end

  it "runs a stopped CIA's TOD divider on" do
    expect(state_differences(stepped(described_class.new, 123_457), skipped(described_class.new, 123_457))).to be_empty
  end
end
