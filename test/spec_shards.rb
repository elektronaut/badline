# frozen_string_literal: true

require "json"

# Splits the spec files into shards of about the same run time, for the
# RSpec jobs' matrix in CI. Each file weighs what it took in a recorded
# run, plain or :slow, and goes to the shard with the least so far, the
# heaviest file first. A file the record doesn't know weighs DEFAULT
# seconds, so a new file still lands in exactly one shard.
class SpecShards
  DEFAULT = 1.0

  # +times+ holds seconds by spec path, as SpecShards.times_from reads them.
  def initialize(files, times)
    @files = files.sort
    @times = times
  end

  # The files of shard +index+ (from 1) of +count+.
  def shard(index, count)
    raise ArgumentError, "no shard #{index} of #{count}" unless index.between?(1, count)

    split(count)[index - 1].sort
  end

  def split(count)
    shards = Array.new(count) { [] }
    loads = Array.new(count, 0.0)
    @files.sort_by { |file| [-weight(file), file] }.each do |file|
      lightest = loads.index(loads.min)
      shards[lightest] << file
      loads[lightest] += weight(file)
    end
    shards
  end

  def weight(file) = @times.fetch(file, DEFAULT)

  # Seconds by spec path from the examples of RSpec JSON formatter
  # reports, rounded to tenths.
  def self.times_from(*reports)
    examples = reports.flat_map { |report| JSON.parse(report).fetch("examples") }
    times = Hash.new(0.0)
    examples.each { |example| times[example.fetch("file_path").delete_prefix("./")] += example.fetch("run_time") }
    times.transform_values { |seconds| seconds.round(1) }.sort.to_h
  end
end
