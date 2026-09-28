# frozen_string_literal: true

module Badline
  module Native
    # `badline --headless` and `--audio-out`: badline-ruby's Audio::CLI,
    # with the audio device reached through Spinel's FFI and the terminal
    # put in raw mode with stty.
    module Headless
      # The factories Audio::CLI calls.
      SINK = ->(rate:, exact_rate:) { AudioSink.new(rate:, exact_rate:) }

      CONSOLE = ->(input:, output:) { Console.new(input:, output:) }

      # Plays or renders the tune and returns the exit status.
      def self.run(options)
        Signal.trap("INT") { raise Interrupt }
        Audio::CLI.new(options, sink: SINK, console: CONSOLE).run
        0
      rescue Audio::CLI::Error => e
        warn "badline: #{e.message}"
        1
      rescue Interrupt
        130
      end
    end
  end
end
