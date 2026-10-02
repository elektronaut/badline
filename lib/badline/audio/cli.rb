# frozen_string_literal: true

module Badline
  module Audio
    # Runs `--headless`, `--audio-out` or `sid`, in either build, once its
    # options have parsed: queues the tunes, each with its subtune and length,
    # then plays them or renders the one to a file. Played on a terminal,
    # the console lets the listener step through the queue.
    class CLI
      class Error < StandardError; end

      # Plays or renders the tunes as #run does, reports an error on stderr
      # under the program's name, and returns the exit status.
      def self.run(options, sink:, console:)
        new(options, sink:, console:).run
        0
      rescue Error => e
        warn "#{options.program}: #{e.message}"
        1
      rescue Interrupt
        130
      end

      # Playing needs `sink`, which builds the audio device given the rate
      # to ask for and whether it has to be exact, and, on a terminal,
      # `console`, which builds the terminal to play on given the input and
      # output. Each build's entry point hands them in: both builds' sink is
      # Frontend::AudioSink, and the console is badline-ruby's Console or
      # the native badline's Native::Console.
      def initialize(options, sink: nil, console: nil, out: $stdout, input: $stdin)
        @options = options
        @out = out
        @input = input
        @sink = sink
        @console = console
        @announced = nil
        @terminal = nil
        @stil_lists = {}
      end

      def run
        @options.render? ? render : play
      rescue Renderer::UnknownFormatError => e
        raise Error, e.message
      end

      # The tunes to play, in the order given. --subtune picks the first
      # one's subtune.
      def queue
        @queue ||= Media::Queue.new(entries, all_parts: @options.all_subtunes?).tap do |queue|
          raise Error, "no .sid tunes in #{@options.tune_paths.join(', ')}" if queue.empty?
        end
      end

      def tune = checked(queue.entry).tune

      def subtune = checked(queue.entry).part

      def seconds = length(subtune)

      def length(subtune) = queue.entry.length(subtune)

      def silence(subtune) = queue.entry.silence(subtune)

      def sid_model = queue.entry.sid_model

      def interactive? = @options.tui? && @input.tty? && @out.tty?

      private

      def entries
        tunes = []
        Media::Queue.files(@options.tune_paths, ".sid").each do |path|
          tunes << QueuedTune.new(path, @options, subtune: tunes.empty? ? @options.subtune : nil)
        end
        tunes
      end

      # A tune on its own has to play, where one of many is skipped.
      def checked(entry)
        raise Error, "#{entry.path}: #{entry.error}" unless entry.error.empty?

        entry
      end

      def renderer(entry, subtune, rate)
        renderer = Renderer.new(entry.tune, seconds: entry.length(subtune), subtune:, rate:, sid_model: entry.sid_model)
        renderer.filter_chunk = @options.filter_chunk if @options.filter_chunk
        renderer.silence = entry.silence(subtune) if entry.silence(subtune)
        renderer
      end

      def render
        entry = checked(queue.entry)
        renderer = renderer(entry, subtune, @options.rate)
        @out.puts describe(entry, subtune)
        entry.notices.each { |line| @out.puts line }
        @out.puts "Rendering #{seconds}s for the #{entry.model_name} to #{@options.audio_out} " \
                  "at #{@options.rate} Hz..."
        started = now
        renderer.render(@options.audio_out) { |done| progress(done, seconds) }
        report(renderer.rendered, now - started)
      end

      def play
        checked(queue.entry) if queue.size == 1
        sink = open_sink
        interactive? ? play_interactively(sink) : play_plainly(sink)
      ensure
        sink&.close
      end

      def play_plainly(sink)
        loop do
          result = play_subtune(sink, queue.entry, queue.part)
          break unless %i[finished skipped].include?(result) && queue.advance
        end
      end

      def play_subtune(sink, entry, subtune)
        return skip(entry) unless entry.error.empty?

        announce(entry, subtune)
        subtune_comments(entry, subtune).each { |line| @out.puts line }
        length = entry.length(subtune)
        @out.puts "Playing #{length}s on the #{entry.model_name} at #{sink.rate} Hz. Ctrl-C stops."
        playback = Playback.new(sink, on_underrun: -> { @out.puts "\rRunning below real time, so it will stutter." })
        renderer = renderer(entry, subtune, sink.rate)
        result = playback.play(renderer) { |played| progress(played, length) }
        progress(renderer.rendered, length) if result == :finished
        @out.print "\n" unless @options.quiet?
        @out.puts(result == :finished ? "Done." : "Stopped.")
        result
      end

      def skip(entry)
        @out.puts "Skipping #{entry.path}: #{entry.error}"
        :skipped
      end

      def announce(entry, subtune)
        @out.puts describe(entry, subtune)
        return if entry.equal?(@announced)

        @announced&.release
        @announced = entry
        (entry.notices + comments(entry)).each { |line| @out.puts line }
      end

      def play_interactively(sink)
        @terminal = @console.call(input: @input, output: @out)
        jukebox = Jukebox.new(sink, @terminal, queue:,
                                               renderer: ->(entry, subtune, rate) { playable(entry, subtune, rate) },
                                               length: ->(entry, subtune) { entry.length(subtune) })
        @terminal.session { jukebox.run }
      end

      # The renderer for the subtune, or nil for a tune the jukebox skips.
      def playable(entry, subtune, rate)
        introduce(entry, rate) unless entry.equal?(@announced)
        return nil unless entry.error.empty?

        comments = subtune_comments(entry, subtune)
        @terminal.announce(comments) unless comments.empty?
        renderer(entry, subtune, rate)
      end

      # Shows the tune's header above the status line as it starts, below
      # the keys the first time.
      def introduce(entry, rate)
        @announced&.release
        lines = introduction(entry, rate)
        @announced.nil? ? @terminal.header(lines) : @terminal.announce(lines)
        @announced = entry
      end

      def introduction(entry, rate)
        return ["Skipping #{entry.path}: #{entry.error}"] unless entry.error.empty?

        entry.header + ["#{entry.model_name} at #{rate} Hz"] + entry.notices + comments(entry)
      end

      def open_sink
        @sink.call(rate: @options.rate, exact_rate: @options.rate_given?)
      rescue Playback::DeviceError => e
        raise Error, "can't open the audio device: #{e.message}"
      end

      def describe(entry, subtune)
        header = entry.header.join(" / ")
        header.empty? ? "subtune #{subtune}" : "#{header} (subtune #{subtune})"
      end

      # The tune's entry in HVSC's STIL, as STIL.txt lays it out.
      def comments(entry)
        found = stil(entry)
        found ? found.fields.flat_map(&:lines) : []
      end

      def subtune_comments(entry, subtune)
        found = stil(entry)
        lines = found ? found.subtune(subtune).flat_map(&:lines) : []
        lines.empty? ? lines : ["(##{subtune})"] + lines
      end

      def stil(entry)
        list = Storage::STIL.locate(entry.path)
        hvsc_path = list && Storage::HVSC.path(entry.path, list)
        hvsc_path && (@stil_lists[list] ||= Storage::STIL.new(list)).entry(hvsc_path)
      end

      def progress(done, total)
        return if @options.quiet?

        @out.print format("\r%<done>6.1fs / %<total>.1fs", done:, total:)
        @out.flush
      end

      def report(rendered, elapsed)
        @out.print "\r" unless @options.quiet?
        @out.puts format("Wrote %<path>s in %<elapsed>.1fs (%<speed>.2fx real time).",
                         path: @options.audio_out, elapsed:, speed: rendered / elapsed)
      end

      def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
