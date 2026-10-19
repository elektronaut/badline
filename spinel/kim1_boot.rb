# frozen_string_literal: true

# Runs a KIM-1 headless. On the keypad it enters INC $10 and a JMP back at
# $0200, then starts it with AD 0200 GO; on a teletype it opens 0200 and
# types the same bytes in with the monitor's . command, then runs them with
# G. Prints a Badline::Support::KIM1Checkpoint every 100,000 cycles, then
# the display, what the teletype printed, the counter, counts and
# registers, and the speed from timed_from on. Builds with Spinel as well
# as running on CRuby:
#
#   ruby --yjit -Ilib spinel/kim1_boot.rb [cycles] [timed_from] [keypad|tty] [ram]
#   spinel -I lib --no-line-map --rbs spinel/sig spinel/kim1_boot.rb -o tmp/spinel/kim1_boot
#   tmp/spinel/kim1_boot [cycles] [timed_from] [keypad|tty] [ram]
#
# ram names one of Badline::KIM1::Bus::RAM_CONFIGURATIONS, 1k by default.

require "badline/core"
require "badline/kim1"
require "badline/support"
require "badline/support/kim1_checkpoint"
require_relative "boot_support"

CHECKPOINT = 100_000

cycles = ARGV[0] ? ARGV[0].to_i : 1_500_000
timed_from = ARGV[1] ? ARGV[1].to_i : 1_000_000
tty = ARGV[2] == "tty"
ram = ARGV[3] || "1k"

machine = Badline::KIM1.new(tty:, ram: ram.to_sym)
machine.type_text(tty ? "0200 E6.10.4C.00.02.0200 G" : "AD 0200 DA E6 + 10 + 4C + 00 + 02 AD 0200 GO")

elapsed = BootSupport.run(machine, cycles, timed_from, CHECKPOINT) do |i|
  puts Badline::Support::KIM1Checkpoint.take(machine) if (i % CHECKPOINT).zero?
end

puts "display #{machine.display_text}"
puts "printed #{machine.teletype.output.delete("\x00").inspect}"
puts "counter #{machine.peek(0x10)}"
BootSupport.print_state(machine)
BootSupport.print_speed(cycles - timed_from, elapsed, 1_000_000)
