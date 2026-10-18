# frozen_string_literal: true

# Saves a P500's snapshot in memory part way through a run, loads it into
# a new machine and runs both on. Prints the size and digest of the
# snapshot's records, inflated, since the two builds deflate them
# differently, whether the new machine saves the same snapshot, digests of
# both machines every million cycles, and whether both save the same
# snapshot at the end. Both type a line that prints in a loop, once
# booted. Builds with Spinel as well as running on CRuby:
#
#   ruby --yjit -Ilib spinel/p500_snapshot.rb [save_at] [cycles] [model]
#   spinel -I lib --no-line-map --rbs spinel/sig spinel/p500_snapshot.rb -o tmp/spinel/p500_snapshot
#   tmp/spinel/p500_snapshot [save_at] [cycles] [model]
#
# model names one of Badline::CBM2::P500::Model::ALL, the PAL 510 by
# default.

require "badline/core"
require "badline/c128"
require "badline/plus4"
require "badline/cbm2"
require "badline/snapshot"
require "badline/support"
require "badline/support/cbm2_checkpoint"
require "badline/support/p500_checkpoint"

CHECKPOINT = 1_000_000

# Each module's name and records, inflated.
def records(image)
  out = +""
  image.sections.each { |section| out << section.name << Zlib.inflate(section.data) }
  out
end

def digest(bytes) = Badline::Support::Checkpoint.fnv1a(bytes.bytes).to_s(16).rjust(8, "0")

def save(machine) = records(Badline::Snapshot::Image.of(machine))

save_at = ARGV[0] ? ARGV[0].to_i : 8_700_000
cycles = ARGV[1] ? ARGV[1].to_i : 10_700_000
model = ARGV[2] || "510"

machine = Badline::CBM2::P500.new(model:)
machine.install_debug_register { |code| puts "debug #{code}" }
machine.run_cycles(save_at)
image = Badline::Snapshot::Image.of(machine)
saved = records(image)
puts "saved at #{machine.cycles}: #{saved.bytesize} bytes, #{digest(saved)}"

restored = Badline::Snapshot::Image.new(Badline::Snapshot::Container.parse(image.to_s)).load do |line|
  puts "left out: #{line}"
end
again = save(restored)
puts "saved again: #{again == saved ? 'the same' : "differs, #{digest(again)}"}"
[machine, restored].each { |each_machine| each_machine.type_text("10 print 6*7;:goto 10\rrun\r") }

while machine.cycles < cycles
  machine.run_cycles(CHECKPOINT)
  restored.run_cycles(CHECKPOINT)
  puts "saved    #{Badline::Support::P500Checkpoint.take(machine)}"
  puts "restored #{Badline::Support::P500Checkpoint.take(restored)}"
end

ours = save(machine)
theirs = save(restored)
puts "at the end: #{ours == theirs ? 'the same' : 'differ'}, #{digest(ours)}"
