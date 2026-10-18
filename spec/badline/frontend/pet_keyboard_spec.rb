# frozen_string_literal: true

require "spec_helper"
require "badline/ffi"
require "badline/frontend"
require_relative "../../support/pet_boot"
require_relative "../../support/cbm2_boot"

describe Badline::Frontend::PETKeyboard do
  subject(:keys) { described_class.new(keyboard, layout) }

  let(:layout) { :graphics }
  let(:matrix) { Badline::PET::KeyboardPorts::GRAPHICS_MATRIX }
  let(:keyboard) { Badline::Input::Keyboard.new(matrix:) }
  let(:shift) { described_class::LSHIFT }

  describe "on the graphics keyboard" do
    it "types \" without SHIFT, though the host's is down" do
      keys.key(shift, true)
      keys.key(52, true)
      expect(keyboard.keys).to eq([:'"'])
    end

    it "puts the host's SHIFT back as the key comes up" do
      keys.key(shift, true)
      keys.key(52, true)
      keys.key(52, false)
      expect(keyboard.keys).to eq([:lshift])
    end

    it "shifts a letter with the host's SHIFT" do
      keys.key(shift, true)
      keys.key(4, true)
      expect(keyboard.keys).to eq(%i[lshift a])
    end

    it "presses RUN/STOP for Esc" do
      keys.key(41, true)
      expect(keyboard.keys).to eq([:run_stop])
    end

    it "types the keypad's digits on the digit keys" do
      keys.key(89, true)
      expect(keyboard.keys).to eq([:"1"])
    end

    it "presses nothing for a key with no PET key" do
      keys.key(58, true)
      expect(keyboard.keys).to eq([])
    end
  end

  describe "on the business keyboard" do
    let(:layout) { :business }
    let(:matrix) { Badline::PET::KeyboardPorts::BUSINESS_MATRIX }

    it "types \" as SHIFT and 2" do
      keys.key(shift, true)
      keys.key(52, true)
      expect(keyboard.keys).to eq(%i[lshift 2])
    end

    it "types @ without SHIFT, though the host's is down" do
      keys.key(shift, true)
      keys.key(31, true)
      expect(keyboard.keys).to eq([:"@"])
    end

    it "presses ESC, TAB and REPEAT for Esc, Tab and Page Up" do
      [41, 43, 75].each { |scancode| keys.key(scancode, true) }
      expect(keyboard.keys).to eq(%i[escape tab repeat])
    end

    it "types the keypad's digits on the keypad" do
      keys.key(98, true)
      expect(keyboard.keys).to eq([:kp0])
    end
  end

  describe "the cursor keys" do
    it "move left with SHIFT and CRSR ⇔" do
      keys.key(80, true)
      expect(keyboard.keys).to eq(%i[lshift cursor_h])
    end

    it "move down with CRSR ⇕ alone, though the host's SHIFT is down" do
      keys.key(shift, true)
      keys.key(81, true)
      expect(keyboard.keys).to eq([:cursor_v])
    end
  end

  describe "with Alt down" do
    let(:alt) { described_class::LALT }

    it "shifts the key a symbol's unshifted character is on" do
      keys.key(alt, true)
      keys.key(52, true)
      expect(keyboard.keys).to contain_exactly(:lshift, :"'")
    end

    it "shifts the key with the host's SHIFT up" do
      keys.key(described_class::RALT, true)
      keys.key(30, true)
      expect(keyboard.keys).to contain_exactly(:lshift, :"1")
    end

    it "keeps SHIFT down until the key comes up, though Alt goes up first" do
      keys.key(alt, true)
      keys.key(54, true)
      keys.key(alt, false)
      expect(keyboard.keys).to contain_exactly(:lshift, :",")
    end

    it "leaves the cursor keys alone" do
      keys.key(alt, true)
      keys.key(81, true)
      expect(keyboard.keys).to eq([:cursor_v])
    end

    it "leaves the keys without a character alone" do
      keys.key(alt, true)
      keys.key(40, true)
      expect(keyboard.keys).to eq([:return])
    end

    context "with the business keyboard" do
      let(:layout) { :business }
      let(:matrix) { Badline::PET::KeyboardPorts::BUSINESS_MATRIX }

      it "shifts the key the unshifted character is on" do
        keys.key(alt, true)
        keys.key(47, true)
        expect(keyboard.keys).to contain_exactly(:lshift, :"[")
      end
    end
  end

  describe "on the CBM-II's keyboard" do
    let(:layout) { :cbm2 }
    let(:matrix) { Badline::CBM2::KeyboardPorts::MATRIX }
    let(:alt) { described_class::LALT }

    it "types \" as SHIFT and '" do
      keys.key(shift, true)
      keys.key(52, true)
      expect(keyboard.keys).to eq(%i[shift '])
    end

    it "types _ on ← without SHIFT, though the host's is down" do
      keys.key(shift, true)
      keys.key(45, true)
      expect(keyboard.keys).to eq([:left_arrow])
    end

    it "types \\ as SHIFT and ←" do
      keys.key(49, true)
      expect(keyboard.keys).to eq(%i[shift left_arrow])
    end

    it "shifts a letter with the host's SHIFT" do
      keys.key(shift, true)
      keys.key(4, true)
      expect(keyboard.keys).to eq(%i[shift a])
    end

    {
      "Esc" => [41, :escape], "F12" => [69, :run_stop], "F1" => [58, :f1], "F8" => [65, :f8],
      "the keypad's 7" => [95, :kp7], "the keypad's Enter" => [88, :kp_enter], "the up arrow" => [82, :cursor_up]
    }.each do |name, (scancode, key)|
      it "presses #{key} for #{name}" do
        keys.key(scancode, true)
        expect(keyboard.keys).to eq([key])
      end
    end

    {
      "C" => [6, :cbm], "E" => [8, :ce], "G" => [10, :norm_graph], "R" => [21, :off_rvs], "P" => [19, :pi],
      "0" => [39, :kp00], "F9" => [66, :f9], "F10" => [67, :f10]
    }.each do |name, (scancode, key)|
      it "presses #{key} for Alt and #{name}" do
        keys.key(alt, true)
        keys.key(scancode, true)
        expect(keyboard.keys).to eq([key])
      end
    end

    it "presses nothing for Alt and a key with no CBM-II key of its own" do
      keys.key(alt, true)
      keys.key(4, true)
      expect(keyboard.keys).to eq([])
    end

    it "holds a key Alt pressed after Alt goes up" do
      keys.key(alt, true)
      keys.key(66, true)
      keys.key(alt, false)
      expect(keys.holds?(66)).to be(true)
    end
  end

  describe "#release_all" do
    it "lets go of every key, SHIFT among them" do
      keys.key(shift, true)
      keys.key(4, true)
      keys.release_all
      expect(keyboard.keys).to eq([])
    end
  end

  describe "typing at READY", :slow do
    include PETBoot

    # The host keys that type each character on a US layout, and whether
    # with SHIFT.
    def stroke(char)
      return [4 + char.ord - 97, false] if char.between?("a", "z")
      return [44, false] if char == " "
      return [40, false] if char == "\r"

      Badline::Frontend::Keys::US_CHARACTERS.each do |scancode, pair|
        return [scancode, pair.index(char) == 1] if scancode < 84 && pair.include?(char)
      end
    end

    # The booted PET's screen as text, after the host's keys type +text+.
    def typed_by_host(model, refresh_hz, text)
      TakenOnce.fetch([:pet_host_keys, model, refresh_hz, text]) do
        pet, = booted_once(model, refresh_hz:, ram_kb: 8)
        host = described_class.new(pet.keyboard, pet.model.keyboard)
        text.each_char { |char| type(pet, host, *stroke(char)) }
        pet.run_cycles(100_000)
        screen_text(pet)
      end
    end

    # Holds the host's SHIFT down a moment before the key, as hands do.
    def type(pet, host, scancode, shifted, cycles = 21_000)
      if shifted
        host.key(described_class::LSHIFT, true)
        pet.run_cycles(cycles)
      end
      host.key(scancode, true)
      pet.run_cycles(cycles)
      host.key(scancode, false)
      host.key(described_class::LSHIFT, false) if shifted
      pet.run_cycles(cycles)
    end

    # The booted PET's screen codes, after the host's keys type the
    # scancodes with Alt down.
    def alt_typed(model, refresh_hz, scancodes)
      TakenOnce.fetch([:pet_alt_keys, model, refresh_hz, scancodes]) do
        pet, = booted_once(model, refresh_hz:, ram_kb: 8)
        host = described_class.new(pet.keyboard, pet.model.keyboard)
        host.key(described_class::LALT, true)
        scancodes.each { |scancode| type(pet, host, scancode, false) }
        host.key(described_class::LALT, false)
        pet.bus.screen.cells.to_a
      end
    end

    def screen_text(pet)
      columns = pet.model.screen_bytes == 0x800 ? 80 : 40
      cells = pet.bus.screen.cells
      Array.new(25) do |row|
        Array.new(columns) do |column|
          code = cells[(row * columns) + column] & 0x7f
          code < 32 ? "@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_"[code] : code.chr
        end.join.rstrip
      end
    end

    [["2001", 60], ["3032", 60], ["3032b", 60], ["4032", 50], ["8032", 50], ["8032", 60]].each do |model, refresh_hz|
      it "prints what the host's keys type on a #{model} at #{refresh_hz} Hz" do
        screen = typed_by_host(model, refresh_hz, "?\"!#&'(*+:;<=>?@[\\]^_a1\"\r")
        expect(screen).to include("!#&'(*+:;<=>?@[\\]^_A1")
      end
    end

    it "prints the graphics on a 3032's symbol keys with Alt" do
      cells = alt_typed("3032", 60, [30, 52, 51])
      expect(cells.each_cons(3)).to include([0x71, 0x67, 0x7b])
    end

    it "prints a graphic and a shifted symbol on an 8032 with Alt" do
      cells = alt_typed("8032", 50, [4, 30])
      expect(cells.each_cons(2)).to include([0x41, 0x21])
    end

    context "with a CBM-II" do
      include CBM2Boot

      def symbols = "!#&'(*+:;<=>?@[\\]^_a1\""

      # The booted 610's screen codes on the line typed, after the host's keys
      # type #symbols, then with Alt down P and 0. The keyboard is scanned
      # once each tick of the 50 Hz mains, 40,000 cycles.
      def cbm2_typed
        TakenOnce.fetch(:cbm2_host_keys) do
          machine = booted
          host = described_class.new(machine.keyboard, :cbm2)
          symbols.each_char { |char| type(machine, host, *stroke(char), 42_000) }
          host.key(described_class::LALT, true)
          [19, 39].each { |scancode| type(machine, host, scancode, false, 42_000) }
          machine.run_cycles(100_000)
          Array.new(80) { |column| machine.bus.peek_bank(15, 0xd000 + (80 * 4) + column) }
        end
      end

      it "prints what the host's keys type" do
        expect(cbm2_typed.first(22))
          .to eq("!#&'(*+:;<=>?".bytes + [0x00, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f, 0x01, 0x31, 0x22])
      end

      it "prints π and 00 with Alt" do
        expect(cbm2_typed[22, 3]).to eq([0x5e, 0x30, 0x30])
      end
    end
  end
end
