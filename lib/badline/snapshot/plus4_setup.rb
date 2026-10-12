# frozen_string_literal: true

module Badline
  module Snapshot
    # How a 264 series machine was built: its model's name, one of
    # Plus4::Model::ALL, which also says whether the Plus/4's function ROMs
    # are fitted, its RAM in K, whether a 1551's TCBM interface is plugged
    # in, the SID card's SID model, or nil without one, and its address,
    # and the RAM expansion's kind, or nil without one, the arguments
    # Plus4.new takes.
    Plus4Setup = Data.define(:model, :ram_kb, :tcbm, :sid_card, :sid_card_address, :ram_expansion)

    class Plus4Setup
      MODELS = Plus4::Model::ALL.map(&:name).freeze

      SID_CARDS = %w[none mos6581 mos8580].freeze

      RAM_EXPANSIONS = ["none", *Plus4::RAMExpansion::KINDS.keys.map(&:to_s)].freeze

      # The setup of `machine`.
      def self.of(machine)
        card = machine.sid_card
        new(model: machine.model.name, ram_kb: machine.ram_kb, tcbm: !machine.tias.empty?, sid_card: card&.model,
            sid_card_address: card ? card.address : Plus4::SIDCard::ADDRESSES.first,
            ram_expansion: machine.ram_expansion&.kind)
      end

      # The model by name, the RAM, the TCBM interface, the SID card's
      # model and address and the RAM expansion's kind, "none" without
      # them, in a keyed snapshot module.
      def write_fields(out)
        out.text("model", model).int("ram_kb", ram_kb).bool("tcbm", tcbm).text("sid_card", (sid_card || :none).to_s)
        out.int("sid_card_address", sid_card_address).text("ram_expansion", (ram_expansion || :none).to_s)
      end

      def self.read_fields(input)
        model = input.choice("model", MODELS, "plus4")
        ram_kb = input.int("ram_kb", Plus4::Model.named(model).ram_kb)
        unless Plus4::Model::RAM_SIZES.include?(ram_kb)
          raise FormatError, "the snapshot is of a Plus/4 with #{ram_kb}K of RAM, which badline doesn't build"
        end

        sid_card = named(input.choice("sid_card", SID_CARDS, "none"))
        ram_expansion = named(input.choice("ram_expansion", RAM_EXPANSIONS, "none"))
        new(model:, ram_kb:, tcbm: input.bool("tcbm", false), sid_card:, sid_card_address: sid_card_address(input),
            ram_expansion:)
      end

      # A choice's name as a Symbol, or nil for "none".
      def self.named(name) = name == "none" ? nil : name.to_sym

      def self.sid_card_address(input)
        address = input.int("sid_card_address", Plus4::SIDCard::ADDRESSES.first)
        return address if Plus4::SIDCard::ADDRESSES.include?(address)

        raise FormatError, format("the snapshot is of a Plus/4 with a SID card at $%<address>04X, " \
                                  "which badline doesn't build", address:)
      end
      private_class_method :named, :sid_card_address

      # A machine built this way, at power-on.
      def build = Plus4.new(model:, ram: ram_kb, tcbm:, sid_card:, sid_card_address:, ram_expansion:)

      def to_s
        parts = ["#{ram_kb}K"]
        parts << "a TCBM interface" if tcbm
        parts << sid_card_part if sid_card
        parts << "a #{ram_expansion} RAM expansion" if ram_expansion
        "#{model} with #{parts.join(' and ')}"
      end

      private

      def sid_card_part
        format("%<article>s %<model>s SID card at $%<address>04X", article: sid_card == :mos8580 ? "an" : "a",
                                                                   model: sid_card.to_s.delete_prefix("mos"),
                                                                   address: sid_card_address)
      end
    end
  end
end
