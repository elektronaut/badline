# frozen_string_literal: true

require "spec_helper"

describe Badline::PET::KeyboardPorts do
  subject(:ports) { described_class.new(keyboard) }

  let(:keyboard) { Badline::Input::Keyboard.new(matrix: described_class::GRAPHICS_MATRIX) }
  let(:ieee) { instance_double(Badline::PET::IEEEPorts, eoi_input: 0xff) }
  let(:cassettes) { instance_double(Badline::PET::Cassettes, sense_input: 0xff) }
  let(:pia) { Badline::Chips::PIA.new(peripheral: ports).tap { |pia| ports.connect(pia, ieee, cassettes) } }

  # What $E812 reads with +row+ written to $E810, as the editor sets it up.
  def scan(row)
    pia.poke(0x00, 0x0f)
    pia.poke(0x01, 0x04)
    pia.poke(0x03, 0x04)
    pia.poke(0x00, row)
    pia.peek(0x02)
  end

  # The key's row times 8 plus its column.
  def position(matrix, key)
    row = matrix.index { |keys| keys.include?(key) }
    (8 * row) + matrix[row].index(key)
  end

  it "reads every column high with no key down" do
    expect(scan(6)).to eq(0xff)
  end

  it "pulls a held key's column low in its own row" do
    keyboard.press(:return)
    expect([scan(6), scan(5)]).to eq([0xdf, 0xff])
  end

  it "selects the row from PA0-PA3 alone" do
    keyboard.press(:a)
    expect(scan(0xf4)).to eq(0xfe)
  end

  it "selects no row past 9" do
    keyboard.press(:rvs)
    expect(scan(10)).to eq(0xff)
  end

  it "reaches the tenth row" do
    keyboard.press(:"=")
    expect(scan(9)).to eq(0x7f)
  end

  it "leaves port A's input lines high" do
    scan(0)
    expect(pia.peek(0x00) & 0xf0).to eq(0xf0)
  end

  # The PETSCII code each editor's key table holds for every key, from
  # the table's end at row 0's PB0 to its start at row 9's PB7.
  {
    "graphics" => [described_class::GRAPHICS_MATRIX, "pet/editor2-n.rom", 0xe6f7,
                   { q: 0x51, "7": 0x37, return: 0x0d, run_stop: 0x03, space: 0x20, cursor_h: 0x1d, "=": 0x3d }],
    "business" => [described_class::BUSINESS_MATRIX, "pet/editor4-80-b-50hz.rom", 0xe6d0,
                   { q: 0x51, "7": 0x37, return: 0x0d, run_stop: 0x03, space: 0x20, kp1: 0xb1, escape: 0x9b,
                     tab: 0x09, repeat: 0x10, "]": 0xdd }]
  }.each do |name, (matrix, rom, table, keys)|
    it "puts the #{name} keys where #{rom} looks them up" do
      codes = Badline::ROM.read(rom)
      expect(keys.keys.to_h { |key| [key, codes[table - 0xe000 + 80 - position(matrix, key)]] }).to eq(keys)
    end
  end
end
