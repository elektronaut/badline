# frozen_string_literal: true

# Runs true-drive scenarios with the same DriveScenarios.run that
# bin/drive_scenarios runs them with, and prints a baseline row per check.
# Takes a scratch directory for the disk images and the scenarios to run.
# Builds with Spinel as well as running on CRuby:
#
#   ruby --yjit -Ilib spinel/drive_scenarios.rb DIR save format
#   spinel -I lib --no-line-map --rbs spinel/sig spinel/drive_scenarios.rb -o tmp/spinel/drive_scenarios
#   tmp/spinel/drive_scenarios DIR save format

require "badline/version"
require "badline/integer_helper"
require "badline/region"
require "badline/addressable"
require "badline/memory"
require "badline/color_memory"
require "badline/rom"
require "badline/ram_expansion"
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
require "badline/via"
require "badline/sid"
require "badline/debug_register"
require "badline/reu"
require "badline/interrupts"
require "badline/traps"
require "badline/cpu"
require "badline/vic"
require "badline/keyboard_buffer"
require "badline/iec_bus"
require "badline/drive1541"
require "badline/computer"
require "badline/storage"
require "badline/cartridge"
require "badline/kernal_trap"
require "badline/chrout_trap"
require "badline/media"
require_relative "../test/drive_scenarios"

raise "Usage: drive_scenarios DIR SCENARIO..." if ARGV.length < 2

dir = ARGV[0]
ARGV.drop(1).each do |name|
  print DriveScenarios.run(name, dir)
  $stdout.flush
end
