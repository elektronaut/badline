# frozen_string_literal: true

require_relative "testbench_machine"

# The machine-driving half of bin/testbench --vic20: building the VIC-20 a
# row asks for, loading its program as xvic's -basicload does, running it
# until it reports through $910F or its budget runs out, and reading back
# the text screen or the display. It stays inside the Ruby subset Spinel compiles, so
# bin/testbench on CRuby and spinel/vic20_testbench.rb on a Spinel build
# run each test the same way.
module Testbench
  # A VIC-20 with the RAM expansion +ram+ names
  # (Badline::Vic20::Bus::RAM_CONFIGURATIONS), booted up to the cycle where
  # a program loads, or left at power-on when +boot+ is false, for a
  # cartridge that has to be in before the first cycle. The VIC doesn't
  # paint its display until a screenshot row's run asks it to.
  def self.vic20_machine(ram, boot)
    machine = Badline::Vic20.new(ram:)
    machine.vic.render = false
    machine.run_cycles(machine.init_threshold) if boot
    machine
  end

  # The text screen where the KERNAL keeps it, at the page in $0288, 23
  # lines of 22 characters, or blank lines before the KERNAL has set it.
  def self.vic20_screen_text(machine)
    ram = machine.ram
    screen = ram.peek(0x0288) << 8
    return Array.new(23) { "" } if screen >= 0x2000

    Array.new(23) { |row| screen_line(ram, screen + (row * 22), 22) }
  end

  # The display cropped to the machine's view, xvic's, as rows of palette
  # indices.
  def self.vic20_screenshot(machine)
    vic = machine.vic
    crop = machine.timing.crop
    display = vic.display
    width = vic.width
    Array.new(crop[3]) { |row| display[((crop[1] + row) * width) + crop[0], crop[2]] }
  end

  # Runs one test on a machine from Testbench.vic20_machine: puts the
  # cartridge's ROM chips, if any, into their blocks, loads the program, if
  # any, then runs until the test writes $910F or the budget runs out. As
  # with VICE's debug cartridge, the run ends on the cycle of the write.
  # Only a screenshot test has the VIC paint its display.
  class Vic20Execution
    attr_reader :exit_code

    def initialize(machine)
      @machine = machine
      @exit_code = nil
      machine.install_debug_register { |value| @exit_code = value }
    end

    def run(render, cartridge, directory, prg, budget)
      @machine.vic.render = render
      insert(cartridge) if cartridge
      basic_load(File.binread(File.join(directory, prg)).bytes) unless prg.empty?
      @machine.run_until(budget) { @exit_code }
      @exit_code
    end

    private

    def insert(path)
      Badline::Storage::CRTFile.new(path, machine: :vic20).chips.each do |chip|
        @machine.bus.map_rom(chip.address, chip.data)
      end
    end

    # As xvic's -basicload: the program goes to the start of BASIC, whatever
    # its load address, BASIC's end of program and the KERNAL's end address
    # are set as LOAD sets them, and RUN goes into the keyboard buffer.
    def basic_load(data)
      ram = @machine.ram
      start = ram.peek16(0x2b)
      ram.write(start, data[2..])
      finish = start + data.length - 2
      [0x2d, 0xae].each { |pointer| ram.write(pointer, [finish & 0xff, finish >> 8]) }
      @machine.type_text("run\r")
    end
  end
end
