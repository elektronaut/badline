# frozen_string_literal: true

# Boots the VIC-20 headless and types a line of BASIC once it is up, or
# attaches and autostarts the media given.
# Prints digests of the machine's parts every quarter million cycles, then
# the screen, counts and registers, and the speed from timed_from on.
# Builds with Spinel as well as running on CRuby:
#
#   ruby --yjit -Ilib spinel/vic20_boot.rb [cycles] [timed_from] [ram] [rate] [media]
#   spinel -I lib --no-line-map --rbs spinel/sig spinel/vic20_boot.rb -o tmp/spinel/vic20_boot
#   tmp/spinel/vic20_boot [cycles] [timed_from] [ram] [rate] [media]
#
# ram names a RAM expansion from Badline::Vic20::Bus::RAM_CONFIGURATIONS,
# or is auto for the one the media asks for (Badline::Media.vic20_ram_for).
# A rate above 0 records the sound at that many samples a second, drained
# once a frame, and the line typed plays a tone on each voice and the
# noise first. The sample count and a checksum of the samples follow the
# registers.

require "badline/core"
require "badline/vic20"

CLOCK_HZ = 1_108_405
CHECKPOINT = 250_000
FRAME = 71 * 312
SOUND = "poke36878,15:poke36874,200:poke36875,215:poke36876,230:poke36877,240:"

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

def fnv1a(values) = Badline::Checkpoint.fnv1a(values)

def via_state(via)
  [via.port_a_output, via.port_b_output, via.timer1, via.timer1_latch, via.timer2,
   via.shift_register.data, via.acr, via.pcr, via.interrupt_flags, via.interrupt_enable]
end

def checkpoint(machine)
  cpu = machine.cpu
  ram = machine.ram
  color_ram = machine.bus.color_ram
  vic = machine.vic
  digests = {
    "cpu" => fnv1a([cpu.program_counter, cpu.a, cpu.x, cpu.y, cpu.stack_pointer, cpu.p, cpu.cycles]),
    "ram" => fnv1a(Array.new(0xc000) { |addr| ram.peek(addr) }),
    "color_ram" => fnv1a(Array.new(0x400) { |offset| color_ram.nibble(offset) }),
    "vic" => fnv1a(vic.register_file + [vic.rasterline, vic.column]),
    "via1" => fnv1a(via_state(machine.via1)),
    "via2" => fnv1a(via_state(machine.via2))
  }
  fields = digests.map { |name, digest| "#{name}=#{digest.to_s(16).rjust(8, '0')}" }
  "#{machine.cycles} #{fields.join(' ')}"
end

cycles = ARGV[0] ? ARGV[0].to_i : 2_000_000
timed_from = ARGV[1] ? ARGV[1].to_i : 1_000_000
media = ARGV[4]
ram = ARGV[2] ? ARGV[2].to_sym : :unexpanded
ram = Badline::Media.vic20_ram_for(media.to_s) if ram == :auto
rate = ARGV[3] ? ARGV[3].to_i : 0

machine = Badline::Vic20.new(ram:)
if media
  puts Badline::Media.attach(machine, media)
else
  line = rate.positive? ? "#{SOUND}print 6*7\r" : "print 6*7\r"
  machine.on_init { machine.type_text(line) }
end
sound = machine.sound_source
sound.record(rate:) if rate.positive?

count = 0
checksum = 0
started = 0.0
i = 0
while i < cycles
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC) if i == timed_from
  stop = ((i / CHECKPOINT) + 1) * CHECKPOINT
  frame_end = ((i / FRAME) + 1) * FRAME
  stop = frame_end if rate.positive? && frame_end < stop
  stop = timed_from if i < timed_from && timed_from < stop
  stop = cycles if cycles < stop
  machine.run_cycles(stop - i)
  i = stop
  puts checkpoint(machine) if (i % CHECKPOINT).zero?
  next unless rate.positive?

  sound.drain_samples.each do |sample|
    checksum = ((checksum * 31) + (sample & 0xffff)) & 0xffffffff
    count += 1
  end
end
elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

screen = machine.ram.peek(0x0288) << 8
row = screen < 0x2000 ? 0 : 23
while row < 23
  line = +""
  col = 0
  while col < 22
    line << screen_char(machine.ram.peek(screen + (row * 22) + col))
    col += 1
  end
  puts line.rstrip
  row += 1
end

cpu = machine.cpu
puts "cycles #{machine.cycles} instructions #{cpu.instructions}"
puts "pc #{cpu.program_counter} a #{cpu.a} x #{cpu.x} y #{cpu.y} p #{cpu.p}"
puts "samples #{count} checksum #{checksum}" if rate.positive?
timed = cycles - timed_from
puts "timed #{timed} cycles in #{(elapsed * 1000).round} ms, " \
     "#{(timed / elapsed / CLOCK_HZ).round(3)}x real time"
