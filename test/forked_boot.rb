# frozen_string_literal: true

# Every testbench and SID test starts from the same machine: 2.5M cycles of
# KERNAL boot, up to the cycle where Media.attach loads the program. A
# runner boots that machine once and forks a child per test from it, so
# each test starts from the booted state without paying for the boot.
#
# Computer#cycle! runs the init handlers at the start of the cycle where
# cycles reaches Computer::INIT_THRESHOLD, and on_init on a machine already
# there runs its block at once. So a child that attaches its program to a
# machine stopped exactly at the threshold loads it before that same cycle
# runs, as a machine that had it attached before boot would.
class ForkedBoot
  # A machine booted to the threshold and not a cycle further.
  def self.computer(**)
    Badline::Computer.new(**).tap do |computer|
      Badline::Computer::INIT_THRESHOLD.times { computer.cycle! }
    end
  end

  # The block boots the machine, and runs in whichever process first needs
  # it, so each shard boots its own.
  def initialize(signals, &boot)
    @signals = signals
    @boot = boot
  end

  # Yields the booted machine in a child and returns what the block
  # returns. A child that raises, dies or outlives the deadline (seconds)
  # leaves the booted machine untouched and returns a crashed or hung
  # result in its place, so the next test still gets a clean fork.
  def run(deadline, &)
    machine
    reader, writer = IO.pipe
    @child = fork { report(reader, writer, &) }
    writer.close
    collect(reader, deadline)
  ensure
    reader&.close
    @child = nil
  end

  private

  # Booted on first use, when this process also starts passing its
  # stopping signals on to the running child.
  def machine
    @machine ||= begin
      forward_signals
      @boot.call
    end
  end

  def report(reader, writer)
    reader.close
    writer.write(yield(@machine).to_s)
    writer.close
    exit!(0)
  rescue StandardError, SystemStackError => e
    writer.write("crashed: #{e.class}: #{e.message}".lines.first.chomp)
    writer.close
    exit!(1)
  end

  def collect(reader, deadline)
    result = read_until(reader, Process.clock_gettime(Process::CLOCK_MONOTONIC) + deadline)
    return hung(deadline) unless result

    status = Process.wait2(@child).last
    return result if status.exited? && !result.empty?

    "crashed: #{status.signaled? ? "SIG#{Signal.signame(status.termsig)}" : "exit #{status.exitstatus}"}"
  end

  # Everything the child wrote, or nil if it was still running at the
  # deadline.
  def read_until(reader, deadline)
    output = +""
    loop do
      remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
      return if remaining <= 0 || !reader.wait_readable(remaining)

      chunk = reader.read_nonblock(4096, exception: false)
      return output if chunk.nil?

      output << chunk unless chunk == :wait_readable
    end
  end

  def hung(deadline)
    Process.kill("KILL", @child)
    Process.wait(@child)
    "hung: killed after #{deadline.round}s"
  end

  # A stopping signal takes the running child down too, then this process
  # dies of it as it would have without the handler.
  def forward_signals
    @signals.each do |signal|
      trap(signal) do
        begin
          Process.kill(signal, @child) if @child
        rescue Errno::ESRCH
          nil
        end
        trap(signal, "DEFAULT")
        Process.kill(signal, Process.pid)
      end
    end
  end
end
