# frozen_string_literal: true

# Saves a PET's snapshot in memory part way through a run, loads it into a
# new machine and runs both on. Prints the size and digest of the
# snapshot's records, inflated, since the two builds deflate them
# differently, whether the new machine saves the same snapshot, digests of
# both machines every quarter million cycles, the picture among them, and
# whether both save the same snapshot at the end. The run types a line
# that rings the bell and writes the screen RAM. Builds with Spinel as well
# as running on CRuby:
#
#   ruby --yjit -Ilib spinel/pet_snapshot.rb [save_at] [cycles] [model] [cpu]
#   spinel -I lib --no-line-map --rbs spinel/sig spinel/pet_snapshot.rb -o tmp/spinel/pet_snapshot
#   tmp/spinel/pet_snapshot [save_at] [cycles] [model] [cpu]
#
# model names one of Badline::PET::Model::ALL, the 8032 by default. The
# superpet's CPU switch is at cpu, 6502 by default; at 6809 it types the
# line at the Waterloo menu, and its checkpoints digest its board, its
# 6809 and its traps too (SuperPETCheckpoint).

require "badline/core"
require "badline/c128"
require "badline/plus4"
require "badline/cbm2"
require "badline/snapshot"
require "badline/support"
require "badline/support/vic20_checkpoint"
require "badline/support/pet_checkpoint"
require "badline/support/superpet_checkpoint"

CHECKPOINT = 250_000

# Each module's name and records, inflated.
def records(image)
  out = +""
  image.sections.each { |section| out << section.name << Zlib.inflate(section.data) }
  out
end

def digest(bytes) = Badline::Support::Checkpoint.fnv1a(bytes.bytes).to_s(16).rjust(8, "0")

def save(machine) = records(Badline::Snapshot::Image.of(machine))

save_at = ARGV[0] ? ARGV[0].to_i : 2_300_000
cycles = ARGV[1] ? ARGV[1].to_i : 3_000_000
model = ARGV[2] || "8032"
cpu = ARGV[3] || "6502"

machine = model == "superpet" ? Badline::PET::SuperPET.new(cpu:) : Badline::PET.new(model:)
machine.on_init { machine.type_text("print chr$(7);:for i=0 to 255:poke 32768+i,i:next\r") }
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
  if model == "superpet"
    puts "saved    #{Badline::Support::SuperPETCheckpoint.take(machine)}"
    puts "restored #{Badline::Support::SuperPETCheckpoint.take(restored)}"
  else
    puts "saved    #{Badline::Support::PETCheckpoint.take(machine)}"
    puts "restored #{Badline::Support::PETCheckpoint.take(restored)}"
  end
end

ours = save(machine)
theirs = save(restored)
puts "at the end: #{ours == theirs ? 'the same' : 'differ'}, #{digest(ours)}"
