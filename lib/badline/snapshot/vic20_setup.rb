# frozen_string_literal: true

module Badline
  module Snapshot
    # How a VIC-20 was built: its RAM expansion, a key of
    # Vic20::Bus::RAM_CONFIGURATIONS, the argument Vic20.new takes.
    Vic20Setup = Data.define(:ram)

    class Vic20Setup
      RAM_CONFIGURATIONS = Vic20::Bus::RAM_CONFIGURATIONS.keys.freeze

      # The RAM expansion by name, in a keyed snapshot module.
      def write_fields(out)
        out.text("ram", ram.to_s)
      end

      def self.read_fields(input)
        text = input.choice("ram", RAM_CONFIGURATIONS.map(&:to_s), "unexpanded")
        new(ram: RAM_CONFIGURATIONS.find { |name| name.to_s == text } || :unexpanded)
      end

      # A machine built this way, at power-on.
      def build = Vic20.new(ram:)

      def to_s = ram.to_s
    end
  end
end
