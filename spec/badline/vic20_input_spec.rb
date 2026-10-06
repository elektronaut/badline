# frozen_string_literal: true

require "spec_helper"
require "badline/vic20"

# The keyboard, the joystick and RESTORE, as the KERNAL and a testprog
# read them on a booted VIC-20.
describe Badline::Vic20, :slow do
  subject(:machine) { described_class.new }

  # The first +rows+ rows of 22 characters on the screen, as text.
  def screen(rows = 8)
    base = machine.ram.peek(0x0288) << 8
    Array.new(rows) do |row|
      Array.new(22) { |col| character(machine.ram.peek(base + (row * 22) + col)) }.join.rstrip
    end
  end

  def character(code)
    code &= 0x7f
    code.between?(1, 26) ? (code + 64).chr : code.chr
  end

  # Holds +keys+ down for two of the KERNAL's keyboard scans, then lets
  # them go for two more.
  def tap(*keys)
    keys.each { |key| machine.keyboard.press(key) }
    machine.run_cycles(40_000)
    keys.each { |key| machine.keyboard.release(key) }
    machine.run_cycles(40_000)
  end

  def boot
    machine.run_cycles(machine.init_threshold)
  end

  describe "#keyboard, typed through the key matrix" do
    before do
      boot
      quote = %i[lshift 2]
      [*%i[p r i n t space].map { [it] }, quote, [:a], quote, *%i[6 * 7 return].map { [it] }].each { tap(*it) }
    end

    it "runs the line typed" do
      expect(screen[5, 2]).to eq(['PRINT "A"6*7', "A 42"])
    end
  end

  describe "#press_restore, with and without RUN/STOP" do
    before do
      machine.type_text("10 print \"x\";:goto 10\rrun\r")
      machine.run_cycles(machine.init_threshold + 300_000)
    end

    def press_restore(*keys)
      keys.each { |key| machine.keyboard.press(key) }
      machine.press_restore
      machine.run_cycles(100_000)
      machine.release_restore
      keys.each { |key| machine.keyboard.release(key) }
      machine.run_cycles(200_000)
    end

    it "warm-starts BASIC with RUN/STOP held" do
      press_restore(:run_stop)
      expect(screen(2)).to eq(["", "READY."])
    end

    # CURLIN's high byte is $FF in direct mode, and 0 on line 10.
    it "lets the program run on without RUN/STOP" do
      press_restore
      expect(machine.ram.peek(0x3a)).to eq(0)
    end
  end

  describe "#joystick1, read by VIC20/joystick/joystick.prg" do
    let(:program) { File.expand_path("../../vendor/VICE-testprogs/VIC20/joystick/joystick.prg", __dir__) }

    before do
      skip "VICE-testprogs not checked out" unless File.exist?(program)
      machine.load_prg(File.binread(program).bytes)
      machine.type_text("sys4110\r")
      machine.run_cycles(machine.init_threshold + 200_000)
    end

    # Where the testprog marks each switch on its screen, around a cross
    # at row 3.
    def marks = { up: 58, left: 79, fire: 80, right: 81, down: 102 }

    def marked
      marks.keys.select { |switch| machine.ram.peek(0x1e00 + marks.fetch(switch)) == "*".ord }
    end

    # What the testprog marks at rest, then with each switch held alone.
    def readings
      [nil, *marks.keys].to_h do |switch|
        machine.joystick1.press(switch)
        machine.run_cycles(20_000)
        machine.joystick1.release(switch)
        [switch, marked]
      end
    end

    it "marks each switch alone, and nothing at rest" do
      expect(readings).to eq(nil => [], up: [:up], left: [:left], fire: [:fire], right: [:right], down: [:down])
    end
  end
end
