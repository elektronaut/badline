# frozen_string_literal: true

module Badline
  module Snapshot
    # How a 264 series machine was built: its model's name, one of
    # Plus4::Model::ALL, which also says whether the Plus/4's function ROMs
    # are fitted, its RAM in K, and whether a 1551's TCBM interface is
    # plugged in, the arguments Plus4.new takes.
    Plus4Setup = Data.define(:model, :ram_kb, :tcbm)

    class Plus4Setup
      MODELS = Plus4::Model::ALL.map(&:name).freeze

      # The setup of `machine`.
      def self.of(machine) = new(model: machine.model.name, ram_kb: machine.ram_kb, tcbm: !machine.tias.empty?)

      # The model by name, the RAM and the TCBM interface, in a keyed
      # snapshot module.
      def write_fields(out)
        out.text("model", model).int("ram_kb", ram_kb).bool("tcbm", tcbm)
      end

      def self.read_fields(input)
        model = input.choice("model", MODELS, "plus4")
        ram_kb = input.int("ram_kb", Plus4::Model.named(model).ram_kb)
        unless Plus4::Model::RAM_SIZES.include?(ram_kb)
          raise FormatError, "the snapshot is of a Plus/4 with #{ram_kb}K of RAM, which badline doesn't build"
        end

        new(model:, ram_kb:, tcbm: input.bool("tcbm", false))
      end

      # A machine built this way, at power-on.
      def build = Plus4.new(model:, ram: ram_kb, tcbm:)

      def to_s = "#{model} with #{ram_kb}K#{' and a TCBM interface' if tcbm}"
    end
  end
end
