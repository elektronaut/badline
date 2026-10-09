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
require_relative "boot_support"

CLOCK_HZ = 1_108_405
CHECKPOINT = 250_000
FRAME = 71 * 312
SOUND = "poke36878,15:poke36874,200:poke36875,215:poke36876,230:poke36877,240:"

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
elapsed = BootSupport.run(machine, cycles, timed_from, CHECKPOINT, rate.positive? ? FRAME : 0) do |i|
  puts checkpoint(machine) if (i % CHECKPOINT).zero?
  if rate.positive?
    sound.drain_samples.each do |sample|
      checksum = ((checksum * 31) + (sample & 0xffff)) & 0xffffffff
      count += 1
    end
  end
end

screen = machine.ram.peek(0x0288) << 8
BootSupport.print_screen(machine.ram, screen, 23, 22) if screen < 0x2000
BootSupport.print_state(machine)
puts "samples #{count} checksum #{checksum}" if rate.positive?
BootSupport.print_speed(cycles - timed_from, elapsed, CLOCK_HZ)
