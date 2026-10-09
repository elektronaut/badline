# frozen_string_literal: true

# Boots the C128 headless and types a line of BASIC once it is up, or
# attaches and autostarts the media given. Prints a
# Badline::Checkpoint every million cycles, then the screen, counts,
# registers and a digest of the VDC's RAM, and the speed from timed_from
# on. Builds with Spinel as well as running on CRuby:
#
#   ruby --yjit -Ilib spinel/c128_boot.rb [cycles] [timed_from] [model] [line] [media]
#   spinel -I lib --no-line-map --rbs spinel/sig spinel/c128_boot.rb -o tmp/spinel/c128_boot
#   tmp/spinel/c128_boot [cycles] [timed_from] [model] [line] [media]
#
# model names one of Badline::C128::Model::ALL. line is "print" for
# `print 6*7`, or "fast" for a line that writes the VDC's RAM and prints
# 6*7 in FAST mode, both in C64 mode, or "basic7" for `print 6*7` in C128
# mode.

require "badline/core"
require "badline/c128"
require_relative "boot_support"

CLOCK_HZ = 985_248
CHECKPOINT = 1_000_000
LINES = {
  "print" => "print 6*7\r",
  "fast" => "poke53296,1:poke54784,31:poke54785,42:print 6*7:poke53296,0\r",
  "basic7" => "print 6*7\r"
}.freeze

cycles = ARGV[0] ? ARGV[0].to_i : 6_000_000
timed_from = ARGV[1] ? ARGV[1].to_i : 3_000_000
model = ARGV[2] || "c128"
line_name = ARGV[3] || "print"
line = LINES.fetch(line_name)

machine = Badline::C128.new(model:, mode: line_name == "basic7" ? :c128 : :c64)
if ARGV[4]
  puts Badline::Media.attach(machine, ARGV[4])
else
  machine.on_init { machine.type_text(line) }
end

elapsed = BootSupport.run(machine, cycles, timed_from, CHECKPOINT) do |i|
  puts Badline::Checkpoint.take(machine) if (i % CHECKPOINT).zero?
end

BootSupport.print_screen(machine.ram, 0x0400, 25, 40)
BootSupport.print_state(machine)
puts "vdc #{Badline::Checkpoint.fnv1a(machine.vdc.ram).to_s(16)} fast #{machine.vic.fast?}"
BootSupport.print_speed(cycles - timed_from, elapsed, CLOCK_HZ)
