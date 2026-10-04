# frozen_string_literal: true

module Badline
  module Snapshot
    # How a machine was built: its VIC, CIA and SID models, its region, its
    # RAM expansion and the size of its REU, the arguments Computer.new
    # takes. A State starts with them, so a machine to restore it into can
    # be built first.
    Setup = Data.define(:vic_model, :cia_model, :sid_model, :region, :ram_expansion, :reu)

    class Setup
      SID_MODELS = %i[mos6581 mos8580].freeze
      REGIONS = [Region::PAL, Region::NTSC, Region::NTSC_OLD].freeze
      RAM_EXPANSIONS = [:none, *RAMExpansion::TYPES.keys].freeze

      def self.of(address_bus)
        new(vic_model: address_bus.vic.model, cia_model: address_bus.cia1.model, sid_model: address_bus.sid.model,
            region: address_bus.region, ram_expansion: address_bus.ram_expansion.type, reu: address_bus.reu&.size_kb)
      end

      def self.read(input)
        new(vic_model: VIC::MODELS.fetch(input.int), cia_model: CIA::MODELS.fetch(input.int),
            sid_model: SID_MODELS.fetch(input.int), region: REGIONS.fetch(input.int),
            ram_expansion: ram_expansion(RAM_EXPANSIONS.fetch(input.int)), reu: reu(input.int))
      rescue IndexError
        raise FormatError, "the state names a chip model, region or RAM expansion badline doesn't know"
      end

      def self.ram_expansion(name) = name == :none ? nil : name

      # An REU's size in K, written as 0 for none.
      def self.reu(size_kb)
        return nil if size_kb.zero?
        return size_kb if REU::SIZES_KB.include?(size_kb)

        raise FormatError, "the state names a #{size_kb}K REU, which badline doesn't build"
      end

      def write(out)
        out.int(VIC::MODELS.index(vic_model)).int(CIA::MODELS.index(cia_model))
        out.int(SID_MODELS.index(sid_model)).int(REGIONS.index(region))
        out.int(RAM_EXPANSIONS.index(ram_expansion || :none)).int(reu || 0)
      end

      # A machine built this way, at power-on.
      def build
        Computer.new(vic_model:, cia_model:, sid_model:, region:, ram_expansion:, reu:)
      end

      # The chips, led by the model's name when they make one of
      # Badline::Model's.
      def to_s
        model = Model.of(self)
        parts = [vic_model, cia_model, sid_model, region.name]
        parts.unshift(model.name) if model
        parts << ram_expansion if ram_expansion
        parts << "a #{reu}K REU" if reu
        parts.join(", ")
      end
    end
  end
end
