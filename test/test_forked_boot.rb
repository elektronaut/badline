# frozen_string_literal: true

require "minitest/autorun"
require_relative "forked_boot"

class TestForkedBoot < Minitest::Test
  def setup
    @boots = 0
    @booted = ForkedBoot.new([]) do
      @boots += 1
      +"booted"
    end
  end

  def test_returns_what_the_child_returns
    assert_equal "booted, ran", @booted.run(10) { |machine| "#{machine}, ran" }
  end

  def test_boots_once_for_every_child
    2.times { @booted.run(10) { "ran" } }

    assert_equal 1, @boots
  end

  def test_a_child_leaves_the_booted_machine_as_it_was
    @booted.run(10) { |machine| machine << " and changed" }

    assert_equal "booted", @booted.run(10) { |machine| machine }
  end

  def test_a_child_that_raises_reports_what_it_raised
    assert_equal "crashed: RuntimeError: boom", @booted.run(10) { raise "boom" }
  end

  def test_a_child_that_dies_reports_the_signal
    assert_equal "crashed: SIGKILL", @booted.run(10) { Process.kill("KILL", Process.pid) }
  end

  def test_a_child_past_its_deadline_is_killed
    assert_equal "hung: killed after 1s", @booted.run(1) { sleep 30 }
  end

  def test_the_next_child_runs_after_one_crashed
    @booted.run(10) { Process.kill("KILL", Process.pid) }

    assert_equal "ran", @booted.run(10) { "ran" }
  end
end

class TestForkedBootSignals < Minitest::Test
  # A process running a child that hangs, standing in for a shard mid-test.
  # It reports the child's PID down the pipe.
  def setup
    reader, writer = IO.pipe
    @parent = fork do
      reader.close
      booted = ForkedBoot.new(%w[TERM]) { "booted" }
      booted.run(60) do
        writer.puts(Process.pid)
        writer.flush
        sleep 60
      end
      exit!(0)
    end
    writer.close
    @child = Integer(reader.gets)
    Process.kill("TERM", @parent)
    @status = Process.wait2(@parent).last
  end

  def teardown
    Process.kill("KILL", @child)
    Process.wait(@child)
  rescue Errno::ESRCH, Errno::ECHILD
    nil
  end

  def test_the_process_dies_of_the_signal
    assert_equal Signal.list["TERM"], @status.termsig
  end

  def test_the_running_child_dies_with_it
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    sleep 0.05 while alive?(@child) && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline

    refute alive?(@child)
  end

  private

  def alive?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH, Errno::EPERM
    false
  end
end
