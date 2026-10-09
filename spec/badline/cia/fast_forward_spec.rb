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

  it "runs a stopped CIA's TOD divider on" do
    expect(state_differences(stepped(described_class.new, 123_457), skipped(described_class.new, 123_457))).to be_empty
  end
end
