# frozen_string_literal: true

require_relative "check"

# Runs the SID testprogs on the Spinel build of spinel/sidtests.rb, split
# into shards side by side. Backs the spinel:sidtests task.
module SpinelSIDTests
  OUT = SpinelCheck::OUT

  module_function

  # Runs the compiled harness over tests (names mapped to their cycle
  # budgets) on the chip sid, and returns the path of their rows, in test
  # order, in the baseline format. TERM or INT is passed on to every
  # shard. Fails unless every shard ran and reported every test it was
  # given.
  def run(suite, tests, sid, shards:)
    names = balance(tests, shards).each_with_index.map do |shard, index|
      name = "#{suite}-#{index + 1}"
      File.write("#{OUT}/#{name}.list", list(shard, sid))
      name
    end
    pids = names.to_h do |name|
      command = [SpinelCheck.binary("sidtests"), "#{OUT}/#{name}.list"]
      puts command.join(" ")
      [Process.spawn(*command, out: "#{OUT}/#{name}.out"), name]
    end
    failed = SpinelCheck.wait_all(pids)
    raise "#{failed.join(', ')} failed." if failed.any?

    results(suite, tests, names)
  end

  # Splits tests into up to count shards of about the same total budget,
  # each keeping the tests' order.
  def balance(tests, count)
    shards = Array.new([count, tests.length].min) { {} }
    tests.sort_by { |_, cycles| -cycles }.each do |name, cycles|
      shards.min_by { |shard| shard.values.sum }[name] = cycles
    end
    shards.map { |shard| tests.select { |name, _| shard.key?(name) } }
  end

  def list(tests, sid)
    lines = ["sid #{sid}", "root #{SIDTests::ROOT}"]
    lines.concat(tests.map { |name, cycles| "test #{cycles} #{name}" })
    "#{lines.join("\n")}\n"
  end

  def results(suite, tests, names)
    rows = names.flat_map { |name| File.readlines("#{OUT}/#{name}.out") }
                .to_h { |line| [line.split("\t", 2).first, line] }
    missing = tests.keys - rows.keys
    raise "The Spinel build reported no row for #{missing.join(', ')}." if missing.any?

    path = "#{OUT}/#{suite}.txt"
    File.write(path, rows.values_at(*tests.keys).join)
    path
  end
end
