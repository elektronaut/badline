# frozen_string_literal: true

module Badline
  module Snapshot
    # How a C64 was built: its VIC, CIA and SID models, its region, its
    # RAM expansion, the size of its REU, its KERNAL, whether it has a
    # datasette and its board, the arguments C64.new takes.
    C64Setup = Data.define(:vic_model, :cia_model, :sid_model, :region, :ram_expansion, :reu, :kernal, :datasette,
                           :board)

    class C64Setup
      SID_MODELS = %i[mos6581 mos8580].freeze
      REGIONS = [Region::PAL, Region::NTSC, Region::NTSC_OLD, Region::DREAN].freeze
      RAM_EXPANSIONS = [:none, *C64::BankedRAM::TYPES.keys].freeze
      KERNALS = C64::Bus::ROMs::KERNALS.keys.freeze
      BOARDS = C64::Bus::Fittings::BOARDS

      def self.of(address_bus)
        new(vic_model: address_bus.vic.model, cia_model: address_bus.cia1.model, sid_model: address_bus.sid.model,
            region: address_bus.region, ram_expansion: address_bus.ram_expansion.type, reu: address_bus.reu&.size_kb,
            kernal: address_bus.kernal, datasette: address_bus.datasette.connected?, board: address_bus.board)
      end

      def self.ram_expansion(name) = name == :none ? nil : name

      # An REU's size in K, written as 0 for none.
      def self.reu(size_kb)
        return nil if size_kb.zero?
        return size_kb if C64::REU::SIZES_KB.include?(size_kb)

        raise FormatError, "the snapshot names a #{size_kb}K REU, which badline doesn't build"
      end

      # The setup in a keyed snapshot module (Snapshot::Keyed), with each
      # model, the region, the RAM expansion, the KERNAL and the board by
      # name.
      def write_fields(out)
        out.text("vic_model", vic_model.to_s).text("cia_model", cia_model.to_s).text("sid_model", sid_model.to_s)
        out.text("region", region.name.to_s).text("ram_expansion", (ram_expansion || :none).to_s)
        out.int("reu_kb", reu || 0).text("kernal", kernal.to_s).bool("datasette", datasette)
        out.text("board", board.to_s)
      end

      # The setup a keyed snapshot module names, a C64's at power-on for
      # anything it leaves out or names that badline doesn't build.
      def self.read_fields(input)
        region = named(input, "region", REGIONS.map(&:name), :pal)
        new(vic_model: named(input, "vic_model", Chips::VIC::MODELS, :mos6569),
            cia_model: named(input, "cia_model", Chips::CIA::MODELS, :mos6526),
            sid_model: named(input, "sid_model", SID_MODELS, :mos6581),
            region: REGIONS.find { |each| each.name == region } || Region::PAL,
            ram_expansion: ram_expansion(named(input, "ram_expansion", RAM_EXPANSIONS, :none)),
            reu: reu(input.int("reu_kb", 0)), kernal: named(input, "kernal", KERNALS, :c64),
            datasette: input.bool("datasette", true), board: named(input, "board", BOARDS, :c64))
      end

      # The Symbol of `names` the text at `key` names.
      def self.named(input, key, names, default)
        text = input.choice(key, names.map(&:to_s), default.to_s)
        names.find { |name| name.to_s == text } || default
      end

      # A machine built this way, at power-on.
      def build
        C64.new(vic_model:, cia_model:, sid_model:, region:, ram_expansion:, reu:, kernal:, datasette:, board:)
      end

      # The chips, led by the model's name when they make one of
      # Badline::Model's.
      def to_s
        model = Model.of(self)
        parts = [vic_model, cia_model, sid_model, region.name]
        parts.unshift(model.name) if model
        parts << ram_expansion if ram_expansion
        parts << "a #{reu}K REU" if reu
        parts << "the #{kernal} KERNAL" unless kernal == :c64
        parts << "no datasette" unless datasette
        parts << "the #{board} board" unless board == :c64
        parts.join(", ")
      end
    end
  end
end
