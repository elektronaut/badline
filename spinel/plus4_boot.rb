# frozen_string_literal: true

# Boots a 264 series machine headless and types `print 6*7` once it is up.
# Prints digests of the CPU, the RAM, the port and the TED every quarter
# million cycles, then the screen, counts and registers, and the speed
# from timed_from on. Builds with Spinel as well as running on CRuby:
#
#   ruby --yjit -Ilib spinel/plus4_boot.rb [cycles] [timed_from] [model]
#   spinel -I lib --no-line-map --rbs spinel/sig spinel/plus4_boot.rb -o tmp/spinel/plus4_boot
#   tmp/spinel/plus4_boot [cycles] [timed_from] [model]
#
# model names one of Badline::Plus4::Model::ALL, the Plus/4 by default.

require "badline/core"
require "badline/plus4"
require "badline/support"
require_relative "boot_support"

CHECKPOINT = 250_000

def fnv1a(values) = Badline::Support::Checkpoint.fnv1a(values)

def ted_state(ted)
  registers = Array.new(0x20) { |register| ted.peek(0xff00 + register) }
  registers + ted.timer_counts + [ted.line, ted.column, ted.interrupt_flags, ted.cpu_slots]
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
    "ted" => fnv1a(ted_state(machine.ted))
  }
  fields = digests.map { |name, digest| "#{name}=#{digest.to_s(16).rjust(8, '0')}" }
  "#{machine.cycles} #{fields.join(' ')}"
end

cycles = ARGV[0] ? ARGV[0].to_i : 1_000_000
timed_from = ARGV[1] ? ARGV[1].to_i : 500_000
model = ARGV[2] || "plus4"

machine = Badline::Plus4.new(model:)
machine.on_init { machine.type_text("print 6*7\r") }

elapsed = BootSupport.run(machine, cycles, timed_from, CHECKPOINT) do |i|
  puts checkpoint(machine) if (i % CHECKPOINT).zero?
end

BootSupport.print_screen(machine.ram, 0x0c00, 25, 40)
BootSupport.print_state(machine)
BootSupport.print_speed(cycles - timed_from, elapsed, machine.model.ted.clock_hz)
