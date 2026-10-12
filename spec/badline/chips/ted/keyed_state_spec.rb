# frozen_string_literal: true

require "spec_helper"
require_relative "../../../support/keyed_oracle"

# The TED's and its sound's keyed fields: a Plus/4's TED saved on any
# cycle, loaded into a fresh one, holds every field the saved one does,
# with the interrupt mask and the raster compare worked out from $FF0A and
# $FF0B. Only the machine it is wired to, whether it paints and which lines
# the front end has yet to show, and the colours the paint last worked out
# for a character, which it works out again before every character, are
# left out. The sound, loaded into a fresh one on the same clock, holds
# every field too, with its frequencies, volume, reload bit and level
# worked out from the TED's registers. A sound is built at cycle 0, as a
# machine builds it.
module TEDKeyedSamples
  extend KeyedOracle

  TED_LEFT_OUT = %i[@bus @keyboard_port @sound @rom_selected @render @dirty_lines @pixel_bits @pixel_colors
                    @multicolor_pixels].freeze
  SOUND_LEFT_OUT = %i[@clock @output].freeze

  # The voices on with the noise, the reload bit set and cleared, a voice
  # stopped at $3FE, the timers written, and a raster interrupt asked for.
  WRITES = { 300 => [[0x11, 0x38], [0x0e, 0x20], [0x12, 0x01], [0x0f, 0x80], [0x10, 0x03]],
             1_500 => [[0x11, 0xb8]], 1_620 => [[0x11, 0x58], [0x0f, 0xfe], [0x10, 0x03]],
             2_400 => [[0x02, 0x40], [0x03, 0x01], [0x0b, 0x30], [0x0a, 0x03], [0x1d, 0x20]] }.freeze

  module_function

  def state(unit, left_out)
    (unit.instance_variables - left_out).to_h { |name| [name, unit.instance_variable_get(name)] }
  end

  def check(machine)
    ted = Badline::Chips::TED.new(machine.ted.profile)
    clock = Struct.new(:cycles).new(0)
    sound = Badline::Chips::TED::Sound.new(clock, machine.model.ted.clock_hz)
    clock.cycles = machine.cycles
    problems = keyed_round_trip(machine.ted, ted).report.lines(verbose: true)
    out = Badline::Snapshot::Keyed::Writer.new
    machine.sound.save_fields(out)
    input = Badline::Snapshot::Keyed::Reader.parse(out.section("BL-TEDSOUND"))
    sound.load_fields(input)
    sound.restored!(ted)
    problems.concat(input.report.lines(verbose: true))
    problems << "differs" unless state(machine.ted, TED_LEFT_OUT) == state(ted, TED_LEFT_OUT)
    problems << "sound differs" unless state(machine.sound, SOUND_LEFT_OUT) == state(sound, SOUND_LEFT_OUT)
    problems.map { |line| "cycle #{machine.cycles}: #{line}" }
  end

  # A Plus/4 from power-on, its KERNAL setting the TED up, with the writes
  # above and the sound recorded, sampled every 499th cycle and on the two
  # cycles after each write.
  def scripted
    machine = Badline::Plus4.new
    machine.sound_source.record(rate: 44_100)
    problems = []
    3_000.times do |cycle|
      WRITES.fetch(cycle, []).each { |register, value| machine.ted.poke(0xff00 + register, value) }
      machine.cycle!
      problems.concat(check(machine)) if (cycle % 499).zero? || WRITES.keys.any? { |at| (cycle - at).between?(0, 1) }
    end
    problems
  end

  # A Plus/4 running BASIC's sound and colour commands, the sound silent,
  # sampled every 97th cycle over most of a frame.
  def basic
    @basic ||= begin
      machine = Badline::Plus4.new
      machine.type_text("10 vol8:sound1,600,30:sound3,800,30\r20 color0,ti/16and15+1:goto20\rrun\r")
      machine.run_cycles(600_000)
      problems = []
      15_000.times do |cycle|
        machine.cycle!
        problems.concat(check(machine)) if (cycle % 97).zero?
      end
      problems
    end
  end
end

describe Badline::Chips::TED::KeyedState do
  it "restores the TED and its sound through a Plus/4's reset" do
    expect(TEDKeyedSamples.scripted.first(5)).to be_empty
  end

  it "restores the TED and its sound while BASIC plays and paints", :slow do
    expect(TEDKeyedSamples.basic.first(5)).to be_empty
  end

  describe "a snapshot from another painter" do
    # Part of the line painted, by a write to the border colour.
    let(:machine) do
      Badline::Plus4.new.tap do |plus4|
        plus4.run_until(5_000) { plus4.cycles > 2_000 && plus4.ted.column == 20 }
        plus4.ted.poke(0xff19, 0x35)
      end
    end
    let(:target) { Badline::Chips::TED.new }

    let(:input) do
      out = Badline::Snapshot::Keyed::Writer.new
      machine.ted.save_fields(out)
      out.int("line.layout", 99)
      Badline::Snapshot::Keyed::Reader.parse(out.section("BL-TED"))
    end

    before { target.load_fields(input) }

    it "paints the line from its start" do
      expect(target.instance_variable_get(:@painted)).to eq(0)
    end

    it "reports the line restarted" do
      expect(input.report.adjusted).to include("line in progress from another renderer, restarted")
    end
  end
end
