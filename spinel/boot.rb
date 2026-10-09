# frozen_string_literal: true

# Boots the machine headless, types a line of BASIC once it is up (or
# attaches and autostarts the media given), and runs on. Prints a
# Badline::Checkpoint every million cycles, then the screen, counts and
# registers, and the speed from timed_from on. Builds with Spinel as well
# as running on CRuby:
#
#   ruby --yjit -Ilib spinel/boot.rb [cycles] [timed_from] [media]
#   spinel -I lib --no-line-map --rbs spinel/sig spinel/boot.rb -o tmp/spinel/boot
#   tmp/spinel/boot [cycles] [timed_from] [media]
#
# Without media the checkpoints match the lines bin/machine_diff prints for
# its type scenario, and with media those for the same media.

require "badline/core"
require_relative "boot_support"

CLOCK_HZ = 985_248
CHECKPOINT = 1_000_000

cycles = ARGV[0] ? ARGV[0].to_i : 6_000_000
timed_from = ARGV[1] ? ARGV[1].to_i : 3_000_000

computer = Badline::Computer.new
if ARGV[2]
  Badline::Media.attach(computer, ARGV[2])
else
  computer.on_init { computer.type_text("print 6*7\r") }
end

elapsed = BootSupport.run(computer, cycles, timed_from, CHECKPOINT) do |i|
  puts Badline::Checkpoint.take(computer) if (i % CHECKPOINT).zero?
end

BootSupport.print_screen(computer.ram, 0x0400, 25, 40)
BootSupport.print_state(computer)
BootSupport.print_speed(cycles - timed_from, elapsed, CLOCK_HZ)
