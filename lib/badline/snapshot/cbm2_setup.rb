# frozen_string_literal: true

module Badline
  module Snapshot
    # How a CBM-II was built: its model's name, one of CBM2::Model::ALL,
    # its KERNAL, one of CBM2::Model::KERNALS, and its mains, 50 or 60 Hz,
    # the arguments CBM2.new takes.
    CBM2Setup = Data.define(:model, :kernal, :mains_hz)

    class CBM2Setup
      MODELS = CBM2::Model::ALL.map(&:name).freeze

      MAINS = [50, 60].freeze

      # The setup of `machine`.
      def self.of(machine) = new(model: machine.model.name, kernal: machine.kernal, mains_hz: machine.mains_hz)

      # The model by name, the KERNAL and the mains, in a keyed snapshot
      # module.
      def write_fields(out)
        out.text("model", model).text("kernal", kernal).int("mains_hz", mains_hz)
      end

      def self.read_fields(input)
        model = input.choice("model", MODELS, CBM2::Model::DEFAULT)
        kernal = input.choice("kernal", CBM2::Model::KERNALS.keys, "04a")
        mains_hz = input.int("mains_hz", 50)
        unless MAINS.include?(mains_hz)
          raise FormatError, "the snapshot is of a CBM-II at #{mains_hz} Hz, which badline doesn't build"
        end

        new(model:, kernal:, mains_hz:)
      end

      # A machine built this way, at power-on.
      def build = CBM2.new(model:, kernal:, mains_hz:)

      def to_s = "#{model} with KERNAL #{kernal} at #{mains_hz} Hz"
    end
  end
end
