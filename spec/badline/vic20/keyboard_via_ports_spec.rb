# frozen_string_literal: true

require "spec_helper"
require "badline/vic20"

describe Badline::Vic20::KeyboardVIAPorts do
  subject(:via) { Badline::VIA.new(start: 0x9120, peripheral: ports) }

  let(:keyboard) { Badline::Keyboard.new(matrix: described_class::MATRIX) }
  let(:joystick) { Badline::Joystick.new }
  let(:ports) { described_class.new(keyboard:, joystick:) }
  let(:kernal) { Badline::ROM.load("vic20/kernal-pal.rom", 0xe000) }

  # What the KERNAL's key table at $EC5E makes of each key, with SHIFT,
  # C= and CTRL read as their flag values 1, 2 and 4.
  codes = {
    "1": 0x31, "2": 0x32, "3": 0x33, "4": 0x34, "5": 0x35, "6": 0x36, "7": 0x37, "8": 0x38, "9": 0x39,
    "0": 0x30, "+": 0x2b, "-": 0x2d, £: 0x5c, clr_home: 0x13, delete: 0x14, left: 0x5f, "*": 0x2a,
    "@": 0x40, up: 0x5e, return: 0x0d, ":": 0x3a, ";": 0x3b, "=": 0x3d, ",": 0x2c, ".": 0x2e, "/": 0x2f,
    space: 0x20, run_stop: 0x03, lshift: 0x01, rshift: 0x01, cbm: 0x02, control: 0x04,
    cursor_h: 0x1d, cursor_v: 0x11, f1: 0x85, f3: 0x86, f5: 0x87, f7: 0x88
  }
  ("a".."z").each { |letter| codes[letter.to_sym] = letter.upcase.ord }

  before do
    ports.connect(via)
    via.poke(0x9122, 0xff)
  end

  # Scans as SCNKEY does: each column low in turn from PB0, the rows read
  # from PA0 up, and the first key down looked up at column * 8 + row.
  def kernal_code
    8.times do |column|
      via.poke(0x9120, 0xff ^ (1 << column))
      rows = via.peek(0x9121)
      row = (0..7).find { |bit| rows.nobits?(1 << bit) }
      return kernal.peek(0xec5e + (column * 8) + row) if row
    end
    nil
  end

  it "wires all 64 keys" do
    expect(described_class::MATRIX.flatten.uniq.length).to eq(64)
  end

  codes.each do |key, code|
    it "puts #{key} where the KERNAL reads $#{code.to_s(16)}" do
      keyboard.press(key)
      expect(kernal_code).to eq(code)
    end
  end

  it "reads every row high with no key down" do
    via.poke(0x9120, 0x00)
    expect(via.peek(0x9121)).to eq(0xff)
  end

  it "reads a key's column on port B while port A drives its row" do
    keyboard.press(:a)
    via.poke(0x9122, 0x00)
    via.poke(0x9123, 0xff)
    via.poke(0x9121, 0b1111_1101)
    expect(via.peek(0x9120)).to eq(0b1111_1011)
  end

  it "reports a ghost key at the fourth corner of three held keys" do
    %i[a s z].each { |key| keyboard.press(key) }
    via.poke(0x9120, 0b1111_1011)
    expect(via.peek(0x9121)).to eq(0b1111_1101)
  end

  describe "the joystick's right switch" do
    before { joystick.press(:right) }

    it "pulls PB7 low while PB7 is an input" do
      via.poke(0x9120, 0xff)
      via.poke(0x9122, 0x7f)
      expect(via.peek(0x9120)).to eq(0x7f)
    end

    it "pulls column 7 low, so a held key in it reads down" do
      keyboard.press(:"2")
      via.poke(0x9120, 0xff)
      expect(via.peek(0x9121)).to eq(0b1111_1110)
    end

    it "leaves the rows high with no key held in column 7" do
      via.poke(0x9120, 0xff)
      expect(via.peek(0x9121)).to eq(0xff)
    end
  end
end
