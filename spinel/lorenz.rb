# frozen_string_literal: true

# Runs the Wolfgang Lorenz chain the way bin/lorenz does, with the same
# Lorenz::Chain, and prints what the run recorded for CRuby to turn into
# baseline rows (Lorenz::Run.parse): a "load OFFSET NAME" line for each
# program the suite loaded, a "key OFFSET" line for each key injected,
# "result RESULT CYCLES", then "transcript LENGTH" and the transcript.
# Builds with Spinel as well as running on CRuby:
#
#   ruby --yjit -Ilib spinel/lorenz.rb image [--resume NAME] [--stop-after NAME]
#   spinel -I lib --no-line-map --rbs spinel/sig spinel/lorenz.rb -o tmp/spinel/lorenz
#   tmp/spinel/lorenz image [--resume NAME] [--stop-after NAME]

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

image = ""
resume = ""
stop_after = ""
i = 0
while i < ARGV.length
  case ARGV[i]
  when "--resume"
    resume = ARGV[i + 1]
    i += 1
  when "--stop-after"
    stop_after = ARGV[i + 1]
    i += 1
  else
    image = ARGV[i]
  end
  i += 1
end
raise "Usage: lorenz image [--resume NAME] [--stop-after NAME]" if image.empty?

print Lorenz.run_chain(image, resume, stop_after, 10_000_000_000)
