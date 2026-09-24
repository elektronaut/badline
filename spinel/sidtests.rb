# frozen_string_literal: true

# Runs a list of SID testprogs the way bin/sidtests does, scoring each with
# the same SIDTests.exit_code, and prints a baseline row per test. The list
# is plain text, as SpinelCheck.run_sidtests writes it:
#
#   sid 6581|8580       the chip every machine is built with
#   root PATH           the directory the test names are under
#   test CYCLES NAME    one per test, in the order to run them
#
# bin/sidtests forks each test from a machine booted once. Without fork,
# each test here boots a fresh machine instead, and attaching at power-on
# loads the program at the same cycle as attaching at the end of the boot.
# Builds with Spinel as well as running on CRuby:
#
#   ruby --yjit -Ilib spinel/sidtests.rb list
#   spinel -I lib --no-line-map --rbs spinel/sig spinel/sidtests.rb -o tmp/spinel/sidtests
#   tmp/spinel/sidtests list

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
require "badline/media"
require_relative "../test/sidtests_machine"
require_relative "debug_register"

module SIDTests
  # Runs every test in the list, each on a fresh machine, and returns their
  # rows. A String in and a String out, so that `spin ext` can export it to
  # CRuby as it stands.
  def self.run_list(list)
    sid_model = :mos6581
    root = ""
    out = +""
    list.each_line do |line|
      key, value = line.chomp.split(" ", 2)
      case key
      when "sid" then sid_model = SID_MODELS.fetch(value)
      when "root" then root = value
      when "test"
        cycles, name = value.split(" ", 2)
        computer = Badline::Computer.new(sid_model:)
        out << record(name, exit_code(computer, File.join(root, name), cycles.to_i))
      end
    end
    out
  end
end

raise "Usage: sidtests list" unless ARGV.length == 1

print SIDTests.run_list(File.read(ARGV[0]))
