# frozen_string_literal: true

# Saves a CBM-II's snapshot in memory part way through a run, loads it into
# a new machine and runs both on. Prints the size and digest of the
# snapshot's records, inflated, since the two builds deflate them
# differently, whether the new machine saves the same snapshot, digests of
# both machines every million cycles, and whether both save the same
# snapshot at the end. Both type a line that prints in a loop, once
# booted. Builds with Spinel as well as running on CRuby:
#
#   ruby --yjit -Ilib spinel/cbm2_snapshot.rb [save_at] [cycles] [model]
#   spinel -I lib --no-line-map --rbs spinel/sig spinel/cbm2_snapshot.rb -o tmp/spinel/cbm2_snapshot
#   tmp/spinel/cbm2_snapshot [save_at] [cycles] [model]
#
# model names one of Badline::CBM2::Model::ALL, the 610 by default.

require "badline/core"
require "badline/c128"
require "badline/plus4"
require "badline/cbm2"
require "badline/kim1"
require "badline/snapshot"
require "badline/support"
require "badline/support/cbm2_checkpoint"

CHECKPOINT = 1_000_000

# Each module's name and records, inflated.
def records(image)
  out = +""
  image.sections.each { |section| out << section.name << Zlib.inflate(section.data) }
  out
end

def digest(bytes) = Badline::Support::Checkpoint.fnv1a(bytes.bytes).to_s(16).rjust(8, "0")

def save(machine) = records(Badline::Snapshot::Image.of(machine))

save_at = ARGV[0] ? ARGV[0].to_i : 8_500_000
cycles = ARGV[1] ? ARGV[1].to_i : 10_500_000
model = ARGV[2] || "610"

machine = Badline::CBM2.new(model:)
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
  puts "saved    #{Badline::Support::CBM2Checkpoint.take(machine)}"
  puts "restored #{Badline::Support::CBM2Checkpoint.take(restored)}"
end

ours = save(machine)
theirs = save(restored)
puts "at the end: #{ours == theirs ? 'the same' : 'differ'}, #{digest(ours)}"
