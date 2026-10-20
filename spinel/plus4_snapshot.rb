# frozen_string_literal: true

# Saves a 264 series machine's snapshot in memory part way through a run,
# loads it into a new machine and runs both on. Prints the size and digest
# of the snapshot's records, inflated, since the two builds deflate them
# differently, whether the new machine saves the same snapshot, digests of
# both machines every quarter million cycles, and whether both save the
# same snapshot at the end. The run plays a tone on voice 1 and the noise
# and types print 6*7. Builds with Spinel as well as running on CRuby:
#
#   ruby --yjit -Ilib spinel/plus4_snapshot.rb [save_at] [cycles] [model]
#   spinel -I lib --no-line-map --rbs spinel/sig spinel/plus4_snapshot.rb -o tmp/spinel/plus4_snapshot
#   tmp/spinel/plus4_snapshot [save_at] [cycles] [model]
#
# model names one of Badline::Plus4::Model::ALL, the Plus/4 by default.

require "badline/core"
require "badline/c128"
require "badline/plus4"
require "badline/cbm2"
require "badline/kim1"
require "badline/snapshot"
require "badline/support"
require "badline/support/plus4_checkpoint"

CHECKPOINT = 250_000

# Each module's name and records, inflated.
def records(image)
  out = +""
  image.sections.each { |section| out << section.name << Zlib.inflate(section.data) }
  out
end

def digest(bytes) = Badline::Support::Checkpoint.fnv1a(bytes.bytes).to_s(16).rjust(8, "0")

def save(machine) = records(Badline::Snapshot::Image.of(machine))

save_at = ARGV[0] ? ARGV[0].to_i : 400_000
cycles = ARGV[1] ? ARGV[1].to_i : 1_000_000
model = ARGV[2] || "plus4"

machine = Badline::Plus4.new(model:)
machine.on_init { machine.type_text("vol8:sound1,700,40:sound3,900,40:print 6*7\r") }
machine.run_cycles(save_at)
image = Badline::Snapshot::Image.of(machine)
saved = records(image)
puts "saved at #{machine.cycles}: #{saved.bytesize} bytes, #{digest(saved)}"

restored = Badline::Snapshot::Image.new(Badline::Snapshot::Container.parse(image.to_s)).load do |line|
  puts "left out: #{line}"
end
again = save(restored)
puts "saved again: #{again == saved ? 'the same' : "differs, #{digest(again)}"}"

while machine.cycles < cycles
  machine.run_cycles(CHECKPOINT)
  restored.run_cycles(CHECKPOINT)
  puts "saved    #{Badline::Support::Plus4Checkpoint.take(machine)}"
  puts "restored #{Badline::Support::Plus4Checkpoint.take(restored)}"
end

ours = save(machine)
theirs = save(restored)
puts "at the end: #{ours == theirs ? 'the same' : 'differ'}, #{digest(ours)}"
