# frozen_string_literal: true

module Badline
  module Snapshot
    # How a CBM-II was built: its model's name, one of CBM2::Model::ALL or
    # CBM2::P500::Model::ALL, its KERNAL, one of the model's KERNALS, its
    # mains, 50 or 60 Hz, and whether the DRAM refresh takes its cycles,
    # the arguments CBM2.new or CBM2::P500.new takes.
    CBM2Setup = Data.define(:model, :kernal, :mains_hz, :refresh)

    class CBM2Setup
      MODELS = (CBM2::Model::ALL + CBM2::P500::Model::ALL).map(&:name).freeze

      KERNALS = (CBM2::Model::KERNALS.keys + CBM2::P500::Model::KERNALS.keys).freeze

      MAINS = [50, 60].freeze

      # The setup of `machine`.
      def self.of(machine)
        new(model: machine.model.name, kernal: machine.kernal, mains_hz: machine.mains_hz, refresh: machine.refresh?)
      end

      # The model by name, the KERNAL, the mains and the refresh, in a keyed
      # snapshot module.
      def write_fields(out)
        out.text("model", model).text("kernal", kernal).int("mains_hz", mains_hz).bool("dram_refresh", refresh)
      end

      def self.read_fields(input)
        model = input.choice("model", MODELS, CBM2::Model::DEFAULT)
        kernal = input.choice("kernal", KERNALS, "04a")
        mains_hz = input.int("mains_hz", 50)
        unless MAINS.include?(mains_hz)
          raise FormatError, "the snapshot is of a CBM-II at #{mains_hz} Hz, which badline doesn't build"
        end

        new(model:, kernal:, mains_hz:, refresh: input.bool("dram_refresh", true))
      end

      # A machine built this way, at power-on.
      def build
        return CBM2::P500.new(model:, mains_hz:) if CBM2::P500::Model.include?(model)

        CBM2.new(model:, kernal:, mains_hz:, refresh:)
      end

      def to_s
        machine = "#{model} with KERNAL #{kernal} at #{mains_hz} Hz"
        refresh || CBM2::P500::Model.include?(model) ? machine : "#{machine} without the DRAM refresh"
      end
    end
  end
end
