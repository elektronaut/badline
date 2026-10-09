# frozen_string_literal: true

module Badline
  class Options
    # One event of --at or --script: what to do, with its argument, once
    # `frame` frames have run. An event given at several frames becomes
    # one Event per frame.
    class Event
      # The actions, and whether each takes an argument. menu's page may be
      # left out.
      ACTIONS = {
        "key" => true, "type" => true, "insert" => true, "eject" => true, "screenshot" => true, "menu" => true,
        "display" => true, "reset" => false, "freeze" => false, "resume" => false, "quit" => false
      }.freeze

      # The frames a key or the freeze button is held for.
      HOLD = 5

      EJECTABLE = %w[disk tape cartridge].freeze

      # The C128's screens display shows: the VIC-IIe's or the VDC's.
      DISPLAYS = %w[vic vdc].freeze

      # What insert takes: disk images, tapes and cartridges, or an .m3u
      # or .vfl list of disks or a directory to mount as device 8.
      INSERTABLE = %w[.d64 .d71 .d81 .g64 .t64 .tap .crt .m3u .vfl].freeze

      attr_reader :frame, :action, :argument

      def initialize(frame, action, argument)
        @frame = frame
        @action = action
        @argument = argument
      end

      # The events of --at's value, or of --script's file.
      def self.given(flag, value)
        return script(value) if flag == "--script"

        events = parse(value)
        raise Error, "invalid argument: #{flag} #{value}" if events.empty?

        events
      end

      # The events of a --script file, one a line in --at's form. Blank
      # lines and lines starting with # are skipped.
      def self.script(path)
        raise Error, "no such file: #{path}" unless File.file?(path)

        events = []
        File.foreach(path) do |line|
          text = line.strip
          events.concat(given("--script #{path}:", text)) unless text.empty? || text.start_with?("#")
        end
        events
      end

      # The events of `FRAME[,FRAME...]:ACTION[=ARGUMENT]`, or an empty list
      # when the text isn't one.
      def self.parse(text)
        colon = text.index(":")
        numbers = colon.nil? ? [] : frames(text[0, colon])
        return [] if numbers.empty?

        event = text[colon + 1, text.size - colon - 1]
        equals = event.index("=")
        action = equals.nil? ? event : event[0, equals]
        argument = equals.nil? ? "" : event[equals + 1, event.size - equals - 1]
        return [] unless valid?(action, argument)

        numbers.map { |frame| new(frame, action, argument) }
      end

      # The frame numbers of `FRAME[,FRAME...]`, or none unless each is a
      # positive number.
      def self.frames(text)
        numbers = text.split(",")
        return [] unless !numbers.empty? && numbers.all? { |number| number.match?(/\A\d+\z/) && number.to_i.positive? }

        numbers.map(&:to_i)
      end

      def self.valid?(action, argument)
        return false unless ACTIONS.key?(action)
        return true if action == "menu"
        return argument.empty? unless ACTIONS[action]
        return EJECTABLE.include?(argument) if action == "eject"
        return DISPLAYS.include?(argument) if action == "display"
        return insertable?(argument) if action == "insert"

        !argument.empty?
      end

      def self.insertable?(path)
        return true if File.directory?(path)

        File.exist?(path) && INSERTABLE.include?(File.extname(path).downcase)
      end
    end
  end
end
