# frozen_string_literal: true

# Boots the machine headless with the SID recording at 44.1 kHz, drained
# once a frame as Audio::MachinePlayer does, or attaches and autostarts the
# media given. Prints the sample count and a checksum of the samples, so
# the Spinel build's audio can be checked sample for sample against
# CRuby's, then the speed from timed_from on. Builds with Spinel as well as
# running on CRuby:
#
#   ruby --yjit -Ilib spinel/sid.rb [cycles] [timed_from] [media]
#   spinel -I lib --no-line-map --rbs spinel/sig spinel/sid.rb -o tmp/spinel/sid
#   tmp/spinel/sid [cycles] [timed_from] [media]

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

CLOCK_HZ = 985_248
FRAME = 19_656

cycles = ARGV[0] ? ARGV[0].to_i : 6_000_000
timed_from = ARGV[1] ? ARGV[1].to_i : 3_000_000

computer = Badline::Computer.new
Badline::Media.attach(computer, ARGV[2]) if ARGV[2]
computer.sid.record(rate: 44_100)

count = 0
checksum = 0
started = 0.0
i = 0
while i < cycles
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC) if i == timed_from
  computer.cycle!
  i += 1
  next unless (i % FRAME).zero? || i == cycles

  computer.sid.drain_samples.each do |sample|
    checksum = ((checksum * 31) + (sample & 0xffff)) & 0xffffffff
    count += 1
  end
end
elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

puts "samples #{count} checksum #{checksum}"
timed = cycles - timed_from
puts "timed #{timed} cycles in #{(elapsed * 1000).round} ms, #{(timed / elapsed / CLOCK_HZ).round(3)}x real time"
