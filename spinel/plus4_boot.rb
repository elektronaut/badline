# frozen_string_literal: true

# Boots a 264 series machine headless and types `print 6*7` once it is up.
# Prints digests of the CPU, the RAM, the port and the TED every quarter
# million cycles, then the screen, counts and registers, and the speed
# from timed_from on. Builds with Spinel as well as running on CRuby:
#
#   ruby --yjit -Ilib spinel/plus4_boot.rb [cycles] [timed_from] [model] [rate]
#   spinel -I lib --no-line-map --rbs spinel/sig spinel/plus4_boot.rb -o tmp/spinel/plus4_boot
#   tmp/spinel/plus4_boot [cycles] [timed_from] [model] [rate]
#
# model names one of Badline::Plus4::Model::ALL, the Plus/4 by default.
# A rate above 0 records the sound at that many samples a second, drained
# once a frame, and the line typed plays a tone on voice 1 and the noise
# first. The sample count and a checksum of the samples follow the
# registers.

require "badline/core"
require "badline/plus4"
require "badline/support"
require_relative "boot_support"

CHECKPOINT = 250_000
FRAME = 57 * 312
SOUND = "vol8:sound1,700,40:sound3,900,40:"

def fnv1a(values) = Badline::Support::Checkpoint.fnv1a(values)

def ted_state(ted)
  registers = Array.new(0x20) { |register| ted.peek(0xff00 + register) }
  registers + ted.timer_counts + [ted.line, ted.column, ted.interrupt_flags, ted.cpu_slots]
end

def sound_state(sound)
  [sound.noise, sound.phase(0), sound.phase(1), sound.level, sound.volume, sound.control]
end

def checkpoint(machine)
  cpu = machine.cpu
  ram = machine.ram
  port = machine.port
  bus = machine.bus
  digests = {
    "cpu" => fnv1a([cpu.program_counter, cpu.a, cpu.x, cpu.y, cpu.stack_pointer, cpu.p, cpu.cycles]),
    "ram" => fnv1a(Array.new(ram.length) { |addr| ram.peek(addr) }),
    "port" => fnv1a([port.ddr, port.data, bus.low_bank, bus.high_bank, bus.rom_selected ? 1 : 0]),
    "ted" => fnv1a(ted_state(machine.ted)),
    "sound" => fnv1a(sound_state(machine.sound))
  }
  fields = digests.map { |name, digest| "#{name}=#{digest.to_s(16).rjust(8, '0')}" }
  "#{machine.cycles} #{fields.join(' ')}"
end

cycles = ARGV[0] ? ARGV[0].to_i : 1_000_000
timed_from = ARGV[1] ? ARGV[1].to_i : 500_000
model = ARGV[2] || "plus4"
rate = ARGV[3] ? ARGV[3].to_i : 0

machine = Badline::Plus4.new(model:)
line = rate.positive? ? "#{SOUND}print 6*7\r" : "print 6*7\r"
machine.on_init { machine.type_text(line) }
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

BootSupport.print_screen(machine.ram, 0x0c00, 25, 40)
BootSupport.print_state(machine)
puts "samples #{count} checksum #{checksum}" if rate.positive?
BootSupport.print_speed(cycles - timed_from, elapsed, machine.model.ted.clock_hz)
