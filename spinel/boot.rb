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

CLOCK_HZ = 985_248

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

computer = Badline::Computer.new
if ARGV[2]
  Badline::Media.attach(computer, ARGV[2])
else
  computer.on_init { computer.type_text("print 6*7\r") }
end

started = 0.0
i = 0
while i < cycles
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC) if i == timed_from
  computer.cycle!
  i += 1
  puts Badline::Checkpoint.take(computer) if (i % 1_000_000).zero?
end
elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

ram = computer.ram
row = 0
while row < 25
  line = +""
  col = 0
  while col < 40
    line << screen_char(ram.peek(0x0400 + (row * 40) + col))
    col += 1
  end
  puts line.rstrip
  row += 1
end

puts "cycles #{computer.cycles} instructions #{computer.cpu.instructions}"
cpu = computer.cpu
puts "pc #{cpu.program_counter} a #{cpu.a} x #{cpu.x} y #{cpu.y} p #{cpu.p}"
timed = cycles - timed_from
puts "timed #{timed} cycles in #{(elapsed * 1000).round} ms, #{(timed / elapsed / CLOCK_HZ).round(3)}x real time"
