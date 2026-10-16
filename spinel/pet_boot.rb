# frozen_string_literal: true

# Boots a PET headless and types `print 6*7` once it is up.
# Prints digests of the CPU, the RAM, the screen, the PIAs, the VIA and the
# CRTC every quarter million cycles, then the screen, counts and
# registers, and the speed from timed_from on. Builds with Spinel as well
# as running on CRuby:
#
#   ruby --yjit -Ilib spinel/pet_boot.rb [cycles] [timed_from] [model] [hz]
#   spinel -I lib --no-line-map --rbs spinel/sig spinel/pet_boot.rb -o tmp/spinel/pet_boot
#   tmp/spinel/pet_boot [cycles] [timed_from] [model] [hz]
#
# model names one of Badline::PET::Model::ALL, the 8032 by default, and
# hz the CRTC editor's frame rate, 50 or 60.

require "badline/core"
require "badline/support"
require_relative "boot_support"

CHECKPOINT = 250_000

def fnv1a(values) = Badline::Support::Checkpoint.fnv1a(values)

def pia_state(pia) = [pia.port_a_output, pia.port_b_output, pia.cra, pia.crb]

def via_state(via)
  [via.port_a_output, via.port_b_output, via.timer1, via.timer1_latch, via.timer2,
   via.shift_register.data, via.acr, via.pcr, via.interrupt_flags, via.interrupt_enable]
end

def checkpoint(machine)
  cpu = machine.cpu
  ram = machine.ram
  crtc = machine.crtc
  digests = {
    "cpu" => fnv1a([cpu.program_counter, cpu.a, cpu.x, cpu.y, cpu.stack_pointer, cpu.p, cpu.cycles]),
    "ram" => fnv1a(Array.new(ram.length) { |addr| ram.peek(addr) }),
    "screen" => fnv1a(machine.bus.screen.cells),
    "pia1" => fnv1a(pia_state(machine.pia1)),
    "pia2" => fnv1a(pia_state(machine.pia2)),
    "via" => fnv1a(via_state(machine.via)),
    "crtc" => fnv1a(crtc.registers + [crtc.column, crtc.line, crtc.row])
  }
  fields = digests.map { |name, digest| "#{name}=#{digest.to_s(16).rjust(8, '0')}" }
  "#{machine.cycles} #{fields.join(' ')}"
end

cycles = ARGV[0] ? ARGV[0].to_i : 2_500_000
timed_from = ARGV[1] ? ARGV[1].to_i : 1_000_000
model = ARGV[2] || "8032"
refresh_hz = ARGV[3] ? ARGV[3].to_i : 50

machine = Badline::PET.new(model:, refresh_hz:)
machine.on_init { machine.type_text("print 6*7\r") }
elapsed = BootSupport.run(machine, cycles, timed_from, CHECKPOINT) do |i|
  puts checkpoint(machine) if (i % CHECKPOINT).zero?
end

screen = machine.bus.screen.cells
columns = screen.length == 0x800 ? 80 : 40
row = 0
while row < 25
  line = +""
  column = 0
  while column < columns
    line << BootSupport.screen_char(screen[(row * columns) + column])
    column += 1
  end
  puts line.rstrip
  row += 1
end
BootSupport.print_state(machine)
BootSupport.print_speed(cycles - timed_from, elapsed, 1_000_000)
