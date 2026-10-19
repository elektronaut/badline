# frozen_string_literal: true

require "spec_helper"

# Waterloo's check, as Dave Roberts transcribed it from the microEditor's
# bank 1 at $9852 (Waterloo-D64-Disk-Patches.pdf, and the Visual 6702's
# macros.js), with each access a few cycles apart as the 6809's are. Seven
# rounds, for bits 7 down to 1, each pushing a byte made from what the chip
# answers; the round for bit n compares the last 8 - n bytes pushed with its
# last read, through a mask each. #passes? when every comparison holds, as
# it does with a 6702 fitted.
class ProtectionCheck
  MASKS = [0x10, 0x80, 0x22, 0x00, 0x40, 0x00, 0x04, 0xa8].freeze

  def initialize(chip, clock)
    @chip = chip
    @clock = clock
  end

  def passes?
    @low = @high = read | 0x11
    pushed = []
    [0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02].each_with_index.all? do |bit, round|
      pushed.unshift(round_for(bit))
      pushed.first(round + 1).each_with_index.all? { |byte, index| byte & MASKS[index] == @last & MASKS[index] }
    end
  end

  private

  def round_for(bit)
    write(bit)
    @high, @low = (@high * @low).divmod(0x100)
    @high |= @low
    pushed = @low ^ 0xd7
    write((read << 1) & 0xff)
    pushed ^= read
    write(@low)
    write((read << 1) & 0xff)
    @last = read
    pushed
  end

  def read
    value = @chip.peek(0xefe0)
    @clock.cycles += 3
    value
  end

  def write(value)
    @chip.poke(0xefe0, value)
    @clock.cycles += 3
  end
end

describe Badline::PET::SuperPET::Dongle do
  subject(:dongle) { described_class.new(clock) }

  let(:clock) { Struct.new(:cycles).new(0) }

  # Runs +ops+, one bus cycle each: "wNN" writes $NN, "r" reads and "i"
  # leaves the chip unselected. Returns what the reads found.
  def run(ops)
    ops.split.filter_map do |op|
      value = op.start_with?("r") ? dongle.peek(0xefe0) : nil
      dongle.poke(0xefe0, op[1, 2].to_i(16)) if op.start_with?("w")
      clock.cycles += 1
      value
    end
  end

  it "reads $D6 from the RES line on, whatever is read" do
    expect(run("r r i r").uniq).to eq([0xd6])
  end

  it "answers a write of each value with the reads the Visual 6702 gives" do
    ops = (0..15).map { |value| "w#{format('%02x', value)} i r" }.join(" ")
    expect(run(ops)).to eq([0xd6, 0xc6, 0xc6, 0x56, 0x56, 0x44, 0x44, 0xd6, 0xd6, 0x84, 0x84, 0x15, 0x15, 0x01,
                            0x01, 0x91])
  end

  # A run of the Visual 6702's netlist from its RES line, where a write
  # that raises D0 shifts the registers at the end of the next cycle.
  it "follows the Visual 6702 through a run of writes, reads and idle cycles" do
    ops = "r r r w1f wf2 r w51 wd9 i wa9 i w0c r i i w9f r w62 wd2 r w32 r r w71 i w54 w14 r i r i r i i wf9 " \
          "wf6 r r wbd w60 r r r i wb4 r w34 wf4 i r w66 r r wa8 w87 r r i w8f r"
    expect(run(ops)).to eq([0xd6, 0xd6, 0xd6, 0xd6, 0xd6, 0xd6, 0xd6, 0xd6, 0xd6, 0xd4, 0xd4, 0xd4, 0x56, 0x56,
                            0xe4, 0xe4, 0xe4, 0xe4, 0xe4, 0xe4, 0xe4, 0xe4, 0xb5, 0xb5])
  end

  it "passes Waterloo's protection check" do
    expect(ProtectionCheck.new(dongle, clock).passes?).to be(true)
  end

  it "passes it again without a reset" do
    ProtectionCheck.new(dongle, clock).passes?
    expect(ProtectionCheck.new(dongle, clock).passes?).to be(true)
  end

  it "fails it with a chip that answers $D6 to everything" do
    chip = instance_double(described_class, peek: 0xd6, poke: nil)
    expect(ProtectionCheck.new(chip, clock).passes?).to be(false)
  end

  it "starts again from the RES line" do
    run("w00 w01 i w00 w01 i")
    dongle.reset!
    expect(run("w00 w01 i r")).to eq([0xc6])
  end
end
