# frozen_string_literal: true

require_relative "testbench_machine"

# The machine-driving half of bin/testbench --pet and --pet-discrete:
# building the PET a row asks for, loading its program to the start of
# BASIC, running it until it reports through $8BFF or its budget runs out,
# and reading back the text screen or the picture. It stays inside the Ruby subset Spinel
# compiles, so bin/testbench on CRuby and spinel/pet_testbench.rb on a
# Spinel build run each test the same way.
module Testbench
  # A PET of +model+ (Badline::PET::Model::ALL) with its own RAM and the
  # 50 Hz editor, booted up to the cycle where a program loads.
  def self.pet_machine(model)
    machine = Badline::PET.new(model:)
    machine.run_cycles(machine.init_threshold)
    machine
  end

  # The text screen, 25 lines of 40 or 80 characters from $8000.
  def self.pet_screen_text(machine)
    screen = machine.bus.screen
    width = machine.model.video == :crtc80 ? 80 : 40
    Array.new(25) { |row| screen_line(screen, row * width, width) }
  end

  # The picture, its rows of palette indices, as xpet's screenshots frame
  # it.
  def self.pet_screenshot(machine)
    canvas = machine.video
    display = canvas.display
    width = canvas.width
    Array.new(canvas.height) { |row| display[row * width, width] }
  end

  # Runs one test on a machine from Testbench.pet_machine: loads the
  # program, or mounts a .d82 as device 8 and loads its first program as
  # Media does, then runs until the test writes $8BFF or the budget runs
  # out.
  class PETExecution
    attr_reader :exit_code

    def initialize(machine)
      @machine = machine
      @exit_code = nil
      machine.install_debug_register { |value| @exit_code = value }
    end

    def run(directory, prg, budget)
      path = File.join(directory, prg)
      if prg.end_with?(".d82")
        @machine.mount(Badline::Storage::D82Image.new(path, read_only: true))
        @machine.type_text(Badline::Media::PETMedia::AUTOSTART)
      else
        basic_load(File.binread(path).bytes)
      end
      @machine.run_until(budget) { @exit_code }
      @exit_code
    end

    private

    # The program goes to the start of BASIC at TXTTAB, whatever its load
    # address, BASIC's end of program at VARTAB and the KERNAL's end
    # address at EAL are set as LOAD sets them, and RUN goes into the
    # keyboard buffer. BASIC 1 keeps the three at $7A, $7C and $E5, and
    # BASIC 2 and 4 at $28, $2A and $C9.
    def basic_load(data)
      ram = @machine.ram
      text, variables, finish_address = @machine.model.basic1? ? [0x7a, 0x7c, 0xe5] : [0x28, 0x2a, 0xc9]
      start = ram.peek16(text)
      ram.write(start, data[2..])
      finish = start + data.length - 2
      [variables, finish_address].each { |pointer| ram.write(pointer, [finish & 0xff, finish >> 8]) }
      @machine.type_text("run\r")
    end
  end
end
