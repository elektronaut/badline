# frozen_string_literal: true

require_relative "taken_once"

# PETs booted once for every spec that reads them, run to the cycle their
# KERNAL has booted by. Each of the other values runs a booted machine on
# from wherever an earlier one left it, idle at READY, and keeps what it
# found for every spec that asks again.
module PETBoot
  # How far the jiffy clock moved and how many times the vertical drive
  # line fell over some cycles.
  Rates = Data.define(:jiffies, :retraces)

  # The machine, with what its screen showed once booted.
  def booted_once(model, refresh_hz: 50, ram_kb: nil)
    TakenOnce.fetch([:pet_booted, model, refresh_hz, ram_kb]) do
      pet = Badline::PET.new(model:, refresh_hz:, ram_kb:)
      pet.run_cycles(pet.init_threshold)
      [pet, screen_of(pet)]
    end
  end

  # The booted machine's Rates over the +cycles+ after the boot.
  def rates_once(model, cycles, refresh_hz: 50, ram_kb: nil)
    TakenOnce.fetch([:pet_rates, model, refresh_hz, ram_kb, cycles]) do
      pet, = booted_once(model, refresh_hz:, ram_kb:)
      jiffies = jiffy_clock(pet)
      retraces = count_retraces(pet, cycles)
      Rates.new(jiffies: jiffy_clock(pet) - jiffies, retraces:)
    end
  end

  # The booted machine's screen after it types +text+ and runs on for
  # +cycles+.
  def typed_once(model, text, cycles, refresh_hz: 50, ram_kb: nil)
    TakenOnce.fetch([:pet_typed, model, refresh_hz, ram_kb, text, cycles]) do
      pet, = booted_once(model, refresh_hz:, ram_kb:)
      pet.type_text(text)
      pet.run_cycles(cycles)
      screen_of(pet, 10)
    end
  end

  # The booted machine's screen after it holds +key+ down on its key
  # matrix for +cycles+, and lets go.
  def pressed_once(model, key, cycles, refresh_hz: 50, ram_kb: nil)
    TakenOnce.fetch([:pet_pressed, model, refresh_hz, ram_kb, key, cycles]) do
      pet, = booted_once(model, refresh_hz:, ram_kb:)
      pet.keyboard.press(key)
      pet.run_cycles(cycles)
      pet.keyboard.release(key)
      pet.run_cycles(cycles)
      screen_of(pet, 10)
    end
  end

  # The screen's first +rows+ rows, as text.
  def screen_of(pet, rows = 6)
    columns = pet.model.screen_bytes == 0x800 ? 80 : 40
    Array.new(rows) do |row|
      Array.new(columns) { |column| character(pet.bus.screen.cells[(row * columns) + column]) }.join.rstrip
    end
  end

  def character(code)
    code &= 0x7f
    code.between?(1, 26) ? (code + 64).chr : code.chr
  end

  # TI, three bytes high byte first, at $8D on BASIC 2 and 4 and at $0200
  # on BASIC 1.
  def jiffy_clock(pet)
    address = pet.model.basic1? ? 0x0200 : 0x8d
    (pet.ram.peek(address) << 16) | (pet.ram.peek(address + 1) << 8) | pet.ram.peek(address + 2)
  end

  def count_retraces(pet, cycles)
    count = 0
    cycles.times do
      high = pet.vertical_drive?
      pet.cycle!
      count += 1 if high && !pet.vertical_drive?
    end
    count
  end
end
