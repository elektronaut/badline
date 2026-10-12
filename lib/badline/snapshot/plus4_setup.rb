# frozen_string_literal: true

module Badline
  module Snapshot
    # How a 264 series machine was built: its model's name, one of
    # Plus4::Model::ALL, which also says whether the Plus/4's function ROMs
    # are fitted, its RAM in K, whether a 1551's TCBM interface is plugged
    # in and the SID card's SID model, or nil without one, the arguments
    # Plus4.new takes.
    Plus4Setup = Data.define(:model, :ram_kb, :tcbm, :sid_card)

    class Plus4Setup
      MODELS = Plus4::Model::ALL.map(&:name).freeze

      SID_CARDS = %w[none mos6581 mos8580].freeze

      # The setup of `machine`.
      def self.of(machine)
        new(model: machine.model.name, ram_kb: machine.ram_kb, tcbm: !machine.tias.empty?,
            sid_card: machine.sid_card&.model)
      end

      # The model by name, the RAM, the TCBM interface and the SID card's
      # model, "none" without one, in a keyed snapshot module.
      def write_fields(out)
        out.text("model", model).int("ram_kb", ram_kb).bool("tcbm", tcbm).text("sid_card", (sid_card || :none).to_s)
      end

      def self.read_fields(input)
        model = input.choice("model", MODELS, "plus4")
        ram_kb = input.int("ram_kb", Plus4::Model.named(model).ram_kb)
        unless Plus4::Model::RAM_SIZES.include?(ram_kb)
          raise FormatError, "the snapshot is of a Plus/4 with #{ram_kb}K of RAM, which badline doesn't build"
        end

        sid_card = input.choice("sid_card", SID_CARDS, "none")
        new(model:, ram_kb:, tcbm: input.bool("tcbm", false), sid_card: sid_card == "none" ? nil : sid_card.to_sym)
      end

      # A machine built this way, at power-on.
      def build = Plus4.new(model:, ram: ram_kb, tcbm:, sid_card:)

      def to_s
        parts = ["#{ram_kb}K"]
        parts << "a TCBM interface" if tcbm
        parts << "#{sid_card == :mos8580 ? 'an' : 'a'} #{sid_card.to_s.delete_prefix('mos')} SID card" if sid_card
        "#{model} with #{parts.join(' and ')}"
      end
    end
  end
end
