# frozen_string_literal: true

# Boots a P500 headless and types `print 6*7` once it is up. Prints a
# Badline::Support::P500Checkpoint every million cycles, then the screen,
# counts and registers, and the speed from timed_from on. Builds with
# Spinel as well as running on CRuby:
#
#   ruby --yjit -Ilib spinel/p500_boot.rb [cycles] [timed_from] [model] [hz]
#   spinel -I lib --no-line-map --rbs spinel/sig spinel/p500_boot.rb -o tmp/spinel/p500_boot
#   tmp/spinel/p500_boot [cycles] [timed_from] [model] [hz]
#
# model names one of Badline::CBM2::P500::Model::ALL, the PAL 510 by
# default, and hz the mains, 50 or 60, the model's region's by default.

require "badline/core"
require "badline/cbm2"
require "badline/support"
require "badline/support/cbm2_checkpoint"
require "badline/support/p500_checkpoint"
require_relative "boot_support"

CHECKPOINT = 1_000_000

cycles = ARGV[0] ? ARGV[0].to_i : 9_500_000
timed_from = ARGV[1] ? ARGV[1].to_i : 1_000_000
model = ARGV[2] || "510"
mains_hz = ARGV[3]&.to_i

machine = Badline::CBM2::P500.new(model:, mains_hz:)
machine.install_debug_register { |code| puts "debug #{code}" }
machine.type_text("print 6*7\r")

elapsed = BootSupport.run(machine, cycles, timed_from, CHECKPOINT) do |i|
  puts Badline::Support::P500Checkpoint.take(machine) if (i % CHECKPOINT).zero?
end

BootSupport.print_screen(machine.bus.screen, 0xd000, 25, 40)
BootSupport.print_state(machine)
puts "segments #{machine.bus.execution_segment} #{machine.bus.indirect_segment}"
BootSupport.print_speed(cycles - timed_from, elapsed, machine.timing.clock_hz)
