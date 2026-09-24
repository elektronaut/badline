# frozen_string_literal: true

module Testbench
  # Runs a shard's tests on a Spinel build of spinel/testbench.rb, which
  # only emulates: it runs each test on a fresh machine and prints what the
  # test left behind, which bin/testbench scores as it scores a test run in
  # process. The tests go to the build as a list, one per line.
  #
  # A test that outlives its deadline is killed with the build running it,
  # and one the build dies on is reported as it died. Either gets a hung or
  # crashed row, and the tests after it run on a new build process.
  class Engine
    # What a test left behind: the exit code it wrote to $D7FF, if any, and
    # the display as rows of palette indices for a screenshot test or the
    # text screen for the others.
    Outcome = Struct.new(:exit_code, :screen)

    RECORD_END = "\ndone\n"

    # A test as a line of the list the build reads.
    def self.spec(test)
      [test.key, test.type, test.budget, (test.cartridge_path if test.cartridge), test.prg, test.dir_abs]
        .join("\t") << "\n"
    end

    # Reads one test's record from the build's output.
    def self.parse(record, test)
      header, exit_line, _cycles, kind, *body = record.lines(chomp: true)
      raise ArgumentError, "Expected #{test.key}, the build reported #{header}" unless header == "test #{test.key}"

      code = exit_line.delete_prefix("exit ")
      screen = kind == "screen" ? body.first(HEIGHT).map { |row| row.chars.map { it.to_i(16) } } : body.first(25)
      Outcome.new(code == "none" ? nil : code.to_i, screen)
    end

    # list is the path the build reads its tests from. spawned is called
    # with the PID of each build process started, and stopped says when
    # the run has been interrupted, when a build that ends is not replaced
    # and its test gets no row.
    def initialize(binary, list, spawned:, stopped:)
      @binary = binary
      @list = list
      @spawned = spawned
      @stopped = stopped
    end

    # Yields each test with its Outcome, or a hung or crashed result, and
    # the seconds it took.
    def run(tests, &)
      tests = run_process(tests, &) until tests.empty? || @stopped.call
    ensure
      FileUtils.rm_f(@list)
    end

    private

    # Runs the tests on one build process, returning those left when one of
    # them hangs or crashes it.
    def run_process(tests)
      File.write(@list, tests.map { |test| Engine.spec(test) }.join)
      reader, writer = IO.pipe
      @pid = Process.spawn(@binary, @list, out: writer)
      writer.close
      @spawned.call(@pid)
      @buffer = +""
      tests.each_with_index do |test, index|
        started = now
        record = read_record(reader, started + test.deadline)
        if record.is_a?(String)
          yield test, Engine.parse(record, test), now - started
        else
          result = ended(record, test.deadline)
          yield test, result, now - started unless @stopped.call
          return tests.drop(index + 1)
        end
      end
      Process.wait(@pid)
      []
    ensure
      reader&.close
    end

    # The next record, or :hung at the deadline, or :ended when the build
    # stopped writing first.
    def read_record(reader, deadline)
      until (finish = @buffer.index(RECORD_END))
        remaining = deadline - now
        return :hung if remaining <= 0 || !reader.wait_readable(remaining)

        chunk = reader.read_nonblock(1 << 16, exception: false)
        return :ended if chunk.nil?

        @buffer << chunk unless chunk == :wait_readable
      end
      @buffer.slice!(0, finish + RECORD_END.length)
    end

    def ended(state, deadline)
      if state == :hung
        kill
        return "hung: killed after #{deadline.round}s"
      end

      status = Process.wait2(@pid).last
      "crashed: #{status.signaled? ? "SIG#{Signal.signame(status.termsig)}" : "exit #{status.exitstatus}"}"
    end

    def kill
      Process.kill("KILL", @pid)
    rescue Errno::ESRCH
      nil
    ensure
      Process.wait(@pid)
    end

    def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
