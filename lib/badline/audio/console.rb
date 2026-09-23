# frozen_string_literal: true

require "io/console"
require "io/wait"

module Badline
  module Audio
    # The terminal face of `badline-sid`: the tune's header, a status line
    # redrawn in place, and single keypresses read without waiting for
    # Return. Ctrl-C still interrupts.
    class Console
      KEYS = {
        "n" => :next, "\e[C" => :next,
        "p" => :previous, "\e[D" => :previous,
        " " => :pause,
        "q" => :quit
      }.freeze

      def initialize(input:, output:)
        @input = input
        @output = output
        @closed = false
      end

      # Raw input and a hidden cursor for the length of the block.
      def session(&)
        @output.print "\e[?25l"
        @input.tty? ? @input.raw(intr: true, &) : yield
      ensure
        @output.print "\e[?25h\r\n"
      end

      # Waits up to `seconds` for keys and returns what they ask for.
      def wait(seconds)
        return idle(seconds) if @closed
        return [] unless @input.wait_readable(seconds)

        case (keys = @input.read_nonblock(64, exception: false))
        when :wait_readable then []
        when nil then close_input(seconds)
        else keys.scan(/\e\[[A-D]|./m).filter_map { |key| KEYS[key] }
        end
      end

      def header(lines)
        lines.each { |line| @output.print "#{line}\r\n" }
        @output.print "n/→ next  p/← previous  space pause  q quit\r\n"
      end

      def status(song:, songs:, elapsed:, length:, notes: [])
        line = format("song %<song>d/%<songs>d  %<elapsed>s / %<length>s",
                      song:, songs:, elapsed: clock(elapsed), length: clock(length))
        @output.print "\r\e[K#{([line] + notes).join('  ')}"
        @output.flush
      end

      private

      def close_input(seconds)
        @closed = true
        idle(seconds)
      end

      def idle(seconds)
        sleep(seconds)
        []
      end

      def clock(seconds)
        whole = seconds.floor
        format("%<minutes>d:%<seconds>02d", minutes: whole / 60, seconds: whole % 60)
      end
    end
  end
end
