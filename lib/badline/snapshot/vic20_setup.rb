# frozen_string_literal: true

module Badline
  module Snapshot
    # How a VIC-20 was built: its RAM expansion, a key of
    # Vic20::Bus::RAM_CONFIGURATIONS, the argument Vic20.new takes.
    Vic20Setup = Data.define(:ram)

    class Vic20Setup
      MARKER = "VIC20"
      RAM_CONFIGURATIONS = Vic20::Bus::RAM_CONFIGURATIONS.keys.freeze

      # The setup a VIC-20's State starts with.
      def self.from(state)
        input = StateReader.new(state)
        input.marker(MARKER)
        input.check_stamp
        read(input)
      end

      def self.read(input)
        new(ram: RAM_CONFIGURATIONS.fetch(input.int))
      rescue IndexError
        raise FormatError, "the state names a VIC-20 RAM expansion badline doesn't know"
      end

      def write(out)
        out.int(RAM_CONFIGURATIONS.index(ram))
      end

      # A machine built this way, at power-on.
      def build = Vic20.new(ram:)

      def to_s = ram.to_s
    end
  end
end
