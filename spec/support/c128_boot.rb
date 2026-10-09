# frozen_string_literal: true

require_relative "taken_once"

# Booted C128s for the specs that run BASIC and the KERNAL, and what their
# screens show.
module C128Boot
  # A machine built for +mode+, with the 40/80 key down when +display_key+,
  # run to the cycle its KERNAL has booted by, once for every example that
  # asks for it. Examples read it, and run on from a machine #booted
  # restores.
  def booted_once(mode = :c64, display_key: false)
    TakenOnce.fetch([:c128_booted, mode, display_key]) do
      Badline::C128.new(mode:).tap do |booting|
        booting.press_display_key if display_key
        booting.run_cycles(booting.init_threshold)
      end
    end
  end

  # A new machine where #booted_once's machine stands.
  def booted(mode = :c64) = Badline::C128.restored(booted_once(mode).snapshot)

  # Runs the machine on to +cycles+ since power-on.
  def run_to(cycles) = machine.run_cycles(cycles - machine.cycles)

  # The first +rows+ rows of the 40-column screen, as text.
  def screen(rows = 25)
    Array.new(rows) do |row|
      Array.new(40) { |col| character(machine.ram.peek(0x0400 + (row * 40) + col)) }.join.rstrip
    end
  end

  def vdc_screen(rows)
    Array.new(rows) { |row| Array.new(80) { |col| character(machine.vdc.ram[(row * 80) + col]) }.join.rstrip }
  end

  def character(code)
    code &= 0x7f
    code.between?(1, 26) ? (code + 64).chr : code.chr
  end

  # 10 PRINT +digit+, for BASIC at $0801 or at $1C01.
  def program(page, digit)
    [0x01, page, 0x09, page, 0x0a, 0x00, 0x99, digit.ord, 0x00, 0x00, 0x00].pack("C*")
  end
end
