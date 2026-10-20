# frozen_string_literal: true

module Badline
  module Snapshot
    # How a KIM-1 was built: its RAM, one of KIM1::Bus::RAM_CONFIGURATIONS
    # by name, the argument KIM1.new takes. The ROMs are the board's own.
    KIM1Setup = Data.define(:ram)

    class KIM1Setup
      RAM = KIM1::Bus::RAM_CONFIGURATIONS.map(&:to_s).freeze

      # The setup of `machine`.
      def self.of(machine) = new(ram: machine.bus.ram_configuration.to_s)

      # The RAM by name, in a keyed snapshot module.
      def write_fields(out)
        out.text("ram", ram)
      end

      def self.read_fields(input) = new(ram: input.choice("ram", RAM, "1k"))

      # A machine built this way, at power-on.
      def build = KIM1.new(ram: ram.to_sym)

      def to_s = "KIM-1 with #{ram == 'expanded' ? 'expanded' : ram.upcase} RAM"
    end
  end
end
