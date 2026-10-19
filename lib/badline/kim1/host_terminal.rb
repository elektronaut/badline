# frozen_string_literal: true

module Badline
  class KIM1
    # The KIM-1's teletype on the host's terminal, for `badline kim1
    # --headless`: what the terminal types goes down the line, and what
    # the teletype prints comes out on it, without the NULs and RUBOUTs a
    # terminal doesn't show. The machine runs at its own 1 MHz against the
    # host's clock, catching up at most CATCH_UP seconds at a time, until
    # Ctrl-C.
    #
    # `console` answers #typing, #read_text and #print_text, as
    # Audio::Terminal does.
    class HostTerminal
      SLICE = 0.01
      CATCH_UP = 0.1

      def self.run(machine, console) = new(machine, console).run

      # Builds the KIM-1 the command line's `options` name, loads the
      # program they name (Media::KIM1Media), and runs it on `console`
      # until Ctrl-C. Returns the exit status, 1 when the program won't
      # load, which it warns about.
      def self.start(options, console)
        path = options.media_path
        machine = Machine.for_options(options, path)
        unless path.nil?
          loaded = Media.attach(machine, path, autostart: true, kim1: Media::KIM1Media.loading(options))
          console.print_text("#{loaded}\r\n")
        end
        run(machine, console)
      rescue Machine::Unsupported, Storage::Papertape::FormatError, SystemCallError => e
        warn "#{options.program}: #{path}: #{e.message}"
        1
      end

      def initialize(machine, console)
        @machine = machine
        @console = console
        @printed = 0
        @started = 0.0
      end

      # Runs until Ctrl-C, and returns the exit status.
      def run
        @started = now
        @console.print_text("KIM-1 teletype at #{@machine.teletype.baud} baud. Ctrl-C: Quit\r\n")
        @console.typing { loop { step } }
      rescue Interrupt
        0
      end

      private

      def step
        text = @console.read_text(SLICE)
        @machine.teletype.type(text) unless text.empty?
        behind = ((now - @started) * 1_000_000).to_i - @machine.cycles
        @machine.run_cycles([behind, (CATCH_UP * 1_000_000).to_i].min) if behind.positive?
        print_output
      end

      def print_output
        output = @machine.teletype.output
        return if output.size == @printed

        @console.print_text(output[@printed, output.size - @printed].gsub("\x00", "").gsub("\x7f", ""))
        @printed = output.size
      end

      def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
