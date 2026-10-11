# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require_relative "../../../support/blank_disk"
require_relative "../../../support/keyed_oracle"

# A 1581's WD1772, mechanism and disk through their keyed fields, against
# their positional state: the controller reading a sector of a D81 and
# writing one, saved now and then, the disk built again from the image the
# module embeds and the tracks it holds.
module Drive1581KeyedSamples
  extend BlankDisk
  extend KeyedOracle

  module_function

  def mechanism_and_fdc
    mechanism = Badline::Drives::Model1581::Mechanism.new
    fdc = Badline::Drives::Model1581::WD1772.new(mechanism)
    disk = Badline::Drives::Model1581::Disk.open(blank_d81(File.join(Dir.mktmpdir, "blank.d81")))
    mechanism.insert(disk, fdc.now)
    mechanism.motor(true, fdc.now)
    fdc.spin_changed
    [mechanism, fdc]
  end

  def through_module
    out = Badline::Snapshot::Keyed::Writer.new
    yield out
    Badline::Snapshot::Keyed::Reader.parse(out.section("BL-TEST"))
  end

  def check(mechanism, fdc)
    inputs = [through_module { |out| fdc.save_fields(out) },
              through_module { |out| mechanism.save_fields(out, fdc.now) },
              through_module { |out| mechanism.disk.save_fields(out) }]
    copy = Badline::Drives::Model1581::Mechanism.new
    copy_fdc = Badline::Drives::Model1581::WD1772.new(copy)
    copy_fdc.load_fields(inputs[0])
    copy.load_fields(inputs[1], Badline::Drives::Model1581::Disk.from_fields(inputs[2]), copy_fdc.now)
    problems = inputs.flat_map { |input| input.report.lines(verbose: true) }
    same = [turned(copy, fdc.now), positional(copy_fdc)] == [turned(mechanism, fdc.now), positional(fdc)]
    problems << "positional state differs" unless same
    problems.map { |line| "cycle #{fdc.now}: #{line}" }
  end

  # The mechanism's positional state with the disk's angle taken as it
  # stands `now`, the one form of it a load keeps.
  def turned(mechanism, now) = positional(with_fields(mechanism, :@angle => mechanism.angle(now), :@since => now))

  # Runs the command to its end, skipping the cycles where nothing
  # happens, as the drive does, and checks every 37th step.
  def run(mechanism, fdc)
    problems = []
    steps = 0
    while fdc.busy? && fdc.now < 5_000_000
      fdc.fast_forward(fdc.quiet_cycles)
      fdc.cycle!
      yield fdc if fdc.drq?
      steps += 1
      problems.concat(check(mechanism, fdc)) if (steps % 37).zero?
    end
    problems
  end

  def samples
    @samples ||= begin
      mechanism, fdc = mechanism_and_fdc
      fdc.poke(2, 1)
      fdc.poke(0, 0x80)
      read = 0
      problems = run(mechanism, fdc) { |chip| read += 1 if chip.peek(3) }
      fdc.poke(0, 0xa0)
      written = 0
      problems += run(mechanism, fdc) { |chip| chip.poke(3, (written += 1) & 0xff) }
      { problems:, read:, written:, changed: mechanism.disk.instance_variable_get(:@changed).keys }
    end
  end
end

describe Badline::Drives::Model1581::KeyedState do
  it "restores the controller, the mechanism and the disk reading and writing a sector" do
    expect(Drive1581KeyedSamples.samples[:problems].first(5)).to be_empty
  end

  it "read a sector and wrote one back to a track" do
    samples = Drive1581KeyedSamples.samples
    expect([samples[:read], samples[:written], samples[:changed]]).to eq([512, 512, [0]])
  end
end
