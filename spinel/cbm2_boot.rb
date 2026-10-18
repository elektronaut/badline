# frozen_string_literal: true

# Boots a CBM-II headless and types `print 6*7` once it is up. Prints a
# Badline::Support::CBM2Checkpoint every million cycles, then the screen,
# counts and registers, and the speed from timed_from on. Builds with
# Spinel as well as running on CRuby:
#
#   ruby --yjit -Ilib spinel/cbm2_boot.rb [cycles] [timed_from] [model] [hz] [kernal]
#   spinel -I lib --no-line-map --rbs spinel/sig spinel/cbm2_boot.rb -o tmp/spinel/cbm2_boot
#   tmp/spinel/cbm2_boot [cycles] [timed_from] [model] [hz] [kernal]
#
# model names one of Badline::CBM2::Model::ALL, the 610 by default, hz the
# mains, 50 or 60, and kernal one of Badline::CBM2::Model::KERNALS.

require "badline/core"
require "badline/cbm2"
require "badline/support"
require "badline/support/cbm2_checkpoint"
require_relative "boot_support"

CHECKPOINT = 1_000_000

cycles = ARGV[0] ? ARGV[0].to_i : 9_000_000
timed_from = ARGV[1] ? ARGV[1].to_i : 1_000_000
model = ARGV[2] || "610"
mains_hz = ARGV[3] ? ARGV[3].to_i : 50
kernal = ARGV[4] || "04a"

machine = Badline::CBM2.new(model:, mains_hz:, kernal:)
machine.install_debug_register { |code| puts "debug #{code}" }
machine.type_text("print 6*7\r")

elapsed = BootSupport.run(machine, cycles, timed_from, CHECKPOINT) do |i|
  puts Badline::Support::CBM2Checkpoint.take(machine) if (i % CHECKPOINT).zero?
end

BootSupport.print_screen(machine.bus.screen, 0xd000, 25, 80)
BootSupport.print_state(machine)
puts "segments #{machine.bus.execution_segment} #{machine.bus.indirect_segment}"
BootSupport.print_speed(cycles - timed_from, elapsed, Badline::CBM2::CLOCK_HZ)
