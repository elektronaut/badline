# frozen_string_literal: true

module Badline
  module Audio
    # The terminal face of `--headless`: the tune's header, a status line
    # redrawn in place, and single keypresses read without waiting for
    # Return. Ctrl-C still interrupts. A subclass puts the terminal in raw
    # mode with #raw! and #restore and waits for keys with #readable?:
    # Console with io/console for badline-ruby, and Native::Console with
    # stty and poll(2) for the native badline.
    class Terminal
      KEYS = {
        "n" => :next, "p" => :previous,
        "\e[C" => :next_subtune, "\e[D" => :previous_subtune,
        " " => :pause,
        "s" => :shuffle,
        "l" => :loop,
        "a" => :all_subtunes,
        "q" => :quit
      }.freeze

      def initialize(input:, output:)
        @input = input
        @output = output
        @closed = false
        @tune = 1
        @tunes = 1
      end

      # Raw input and a hidden cursor for the length of the block.
      def session
        @output.print "\e[?25l"
        mode = raw! if @input.tty?
        yield
      ensure
        restore(mode) if mode
        @output.print "\e[?25h\r\n"
      end

      # Waits up to `seconds` for keys and returns what they ask for.
      def wait(seconds)
        return idle(seconds) if @closed
        return [] unless readable?(seconds)

        case (keys = @input.read_nonblock(64, exception: false))
        when :wait_readable then []
        when nil then close_input(seconds)
        else keys.scan(/\e\[[A-D]|./m).filter_map { |key| KEYS[key] }
        end
      end

      def header(lines)
        lines.each { |line| @output.print "#{line}\r\n" }
        @output.print "←/→ subtune  n/p tune  space pause  s shuffle  l loop  a all subtunes  q quit\r\n"
      end

      # Prints lines above the status line, such as the next tune's header.
      def announce(lines)
        lines.each { |line| @output.print "\r\e[K#{line}\r\n" }
      end

      # The tune's place in the queue, which the status line shows once
      # there is more than one.
      def place(tune, tunes)
        @tune = tune
        @tunes = tunes
      end

      def status(subtune:, subtunes:, elapsed:, length:, notes: [])
        line = format("subtune %<subtune>d/%<subtunes>d  %<elapsed>s / %<length>s",
                      subtune:, subtunes:, elapsed: clock(elapsed), length: clock(length))
        line = format("tune %<tune>d/%<tunes>d  %<line>s", tune: @tune, tunes: @tunes, line:) if @tunes > 1
        @output.print "\r\e[K#{([line] + notes).join('  ')}"
        @output.flush
      end

      private

      # A subclass puts the terminal in raw mode and returns the mode to
      # restore afterwards.
      def raw! = nil

      def restore(mode) = mode

      # A subclass waits up to `seconds` for input and says whether any
      # came.
      def readable?(seconds)
        sleep(seconds)
        false
      end

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
