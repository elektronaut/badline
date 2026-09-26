# frozen_string_literal: true

# Lorenz.run_chain, the kernel of spinel/lorenz.rb, which drives it as a
# binary. `EXT=1 rake spinel:lorenz` compiles this file with `spinel --ext
# cruby` into an extension CRuby calls in process, so it holds no driver.

require "badline/version"
require "badline/integer_helper"
require "badline/addressable"
require "badline/memory"
require "badline/color_memory"
require "badline/rom"
require "badline/address_bus"
require "badline/instruction"
require "badline/instruction_set"
require "badline/status"
require "badline/keyboard"
require "badline/joystick"
require "badline/control_ports"
require "badline/input"
require "badline/cycleable"
require "badline/datasette"
require "badline/time_of_day"
require "badline/cia"
require "badline/sid"
require "badline/debug_register"
require "badline/interrupts"
require "badline/traps"
require "badline/cpu"
require "badline/vic"
require "badline/keyboard_buffer"
require "badline/computer"
require "badline/storage"
require "badline/cartridge"
require "badline/kernal_trap"
require "badline/chrout_trap"
require_relative "../test/lorenz_chain"

module Lorenz
  # Runs the chain on a fresh machine and returns what it recorded. An
  # empty resume starts the chain from the top, and an empty stop_after
  # runs it to the end. Strings and Integers in, a String out, so that
  # `spin ext` can export it to CRuby as it stands.
  def self.run_chain(image, resume, stop_after, max_cycles)
    computer = Badline::Computer.new
    computer.vic.render = false
    capture = computer.capture_output
    disk = mount(computer, image, capture, (resume unless resume.empty?))
    chain = Chain.new(computer, capture, disk, max_cycles, (stop_after unless stop_after.empty?))
    chain.step until chain.result

    out = +""
    offsets = disk.offsets
    disk.names.each_with_index { |name, index| out << "load #{offsets[index]} #{name}\n" }
    chain.key_offsets.each { |offset| out << "key #{offset}\n" }
    out << "result #{chain.result} #{computer.cycles}\n"
    out << "transcript #{capture.output.length}\n"
    out << capture.output
  end
end
