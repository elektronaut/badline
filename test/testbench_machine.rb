# frozen_string_literal: true

# The machine-driving half of the VICE testbench runner: attaching a test's
# media, running it until it reports or its budget runs out, and reading
# back the display and the text screen. It stays inside the Ruby subset
# Spinel compiles, so bin/testbench on CRuby and spinel/testbench.rb on a
# Spinel build run each test the same way.
module Testbench
  # Boot + RUN typing overhead on top of the testlist cycle budgets, which
  # assume VICE's own autostart.
  BOOT_ALLOWANCE = 3_000_000
  BATCH = 10_000

  # The VICE PAL viewport crop of the VIC display, matching the 384x272
  # reference screenshots (the GUI ScreenPane crops 4 lines lower).
  WIDTH = 384
  HEIGHT = 272
  COL_OFFSET = 96
  ROW_OFFSET = 16

  # A power-on machine for a test with a cartridge, which starts it the way
  # VICE does, and otherwise one booted up to the cycle where an attached
  # program loads (see test/forked_boot.rb), with the CIAs the test asks
  # for.
  def self.machine(cartridge, cia_model = :mos6526)
    computer = Badline::Computer.new(cia_model:)
    Badline::Computer::INIT_THRESHOLD.times { computer.cycle! } unless cartridge
    computer
  end

  # The display cropped to the reference screenshots, as rows of palette
  # indices.
  def self.screenshot(vic)
    display = vic.display
    width = vic.width
    Array.new(HEIGHT) { |row| display[((row + ROW_OFFSET) * width) + COL_OFFSET, WIDTH] }
  end

  # The text screen at $0400, 25 lines of 40 characters.
  def self.screen_text(ram)
    Array.new(25) { |row| screen_line(ram, 0x0400 + (row * 40)) }
  end

  def self.screen_line(ram, address)
    line = +""
    40.times { |col| line << screen_ascii(ram.peek(address + col)) }
    line
  end

  def self.screen_ascii(code)
    code &= 0x7f
    case code
    when 0x01..0x1a then (code + 0x60).chr
    when 0x00, 0x1b..0x1f then (code + 0x40).chr
    when 0x20..0x3f, 0x41..0x5a then code.chr
    else " "
    end
  end

  # Runs one test on a machine from Testbench.machine: attaches the
  # cartridge, if any, and the program, if any, from the test's directory
  # mounted as device 8, then runs until the test writes $D7FF or the
  # budget runs out. Only a screenshot test reads the display, so the
  # others run with the VIC's colours unpainted.
  class Execution
    attr_reader :exit_code

    def initialize(computer)
      @computer = computer
      @exit_code = nil
      computer.install_debug_register { |value| @exit_code = value }
    end

    def run(render, cartridge, directory, prg, budget)
      @computer.vic.render = render
      Badline::Media.attach(@computer, cartridge) if cartridge
      unless prg.empty?
        @computer.mount(Badline::Storage::HostDirectory.new(directory))
        Badline::Media.attach(@computer, File.join(directory, prg))
      end
      BATCH.times { @computer.cycle! } until @exit_code || @computer.cycles > budget
      @exit_code
    end
  end
end
