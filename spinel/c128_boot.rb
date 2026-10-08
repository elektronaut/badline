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

CLOCK_HZ = 985_248
LINES = {
  "print" => "print 6*7\r",
  "fast" => "poke53296,1:poke54784,31:poke54785,42:print 6*7:poke53296,0\r",
  "basic7" => "print 6*7\r"
}.freeze

def screen_char(code)
  code &= 0x7f
  if code.zero?
    "@"
  elsif code < 27
    (code + 96).chr
  elsif code < 64
    code.chr
  else
    "."
  end
end

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

started = 0.0
i = 0
while i < cycles
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC) if i == timed_from
  stop = ((i / 1_000_000) + 1) * 1_000_000
  stop = timed_from if i < timed_from && timed_from < stop
  stop = cycles if cycles < stop
  machine.run_cycles(stop - i)
  i = stop
  puts Badline::Checkpoint.take(machine) if (i % 1_000_000).zero?
end
elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

ram = machine.ram
row = 0
while row < 25
  text = +""
  col = 0
  while col < 40
    text << screen_char(ram.peek(0x0400 + (row * 40) + col))
    col += 1
  end
  puts text.rstrip
  row += 1
end

cpu = machine.cpu
puts "cycles #{machine.cycles} instructions #{cpu.instructions}"
puts "pc #{cpu.program_counter} a #{cpu.a} x #{cpu.x} y #{cpu.y} p #{cpu.p}"
puts "vdc #{Badline::Checkpoint.fnv1a(machine.vdc.ram).to_s(16)} fast #{machine.vic.fast?}"
timed = cycles - timed_from
puts "timed #{timed} cycles in #{(elapsed * 1000).round} ms, #{(timed / elapsed / CLOCK_HZ).round(3)}x real time"
