# frozen_string_literal: true

module Badline
  module Snapshot
    # How a machine was built: its VIC, CIA and SID models, its region and
    # its RAM expansion, the arguments Computer.new takes. A State starts
    # with them, so a machine to restore it into can be built first.
    class Setup
      SID_MODELS = %i[mos6581 mos8580].freeze
      REGIONS = [Region::PAL, Region::NTSC].freeze
      RAM_EXPANSIONS = [:none, *RAMExpansion::TYPES.keys].freeze

      attr_reader :vic_model, :cia_model, :sid_model, :region, :ram_expansion

      def self.of(address_bus)
        new(vic_model: address_bus.vic.model, cia_model: address_bus.cia1.model, sid_model: address_bus.sid.model,
            region: address_bus.region, ram_expansion: address_bus.ram_expansion.type)
      end

      def self.read(input)
        new(vic_model: VIC::MODELS.fetch(input.int), cia_model: CIA::MODELS.fetch(input.int),
            sid_model: SID_MODELS.fetch(input.int), region: REGIONS.fetch(input.int),
            ram_expansion: ram_expansion(RAM_EXPANSIONS.fetch(input.int)))
      rescue IndexError
        raise FormatError, "the state names a chip model, region or RAM expansion badline doesn't know"
      end

      def self.ram_expansion(name) = name == :none ? nil : name

      def initialize(vic_model:, cia_model:, sid_model:, region:, ram_expansion:)
        @vic_model = vic_model
        @cia_model = cia_model
        @sid_model = sid_model
        @region = region
        @ram_expansion = ram_expansion
      end

      def write(out)
        out.int(VIC::MODELS.index(@vic_model)).int(CIA::MODELS.index(@cia_model))
        out.int(SID_MODELS.index(@sid_model)).int(REGIONS.index(@region))
        out.int(RAM_EXPANSIONS.index(@ram_expansion || :none))
      end

      # A machine built this way, at power-on.
      def build
        Computer.new(vic_model: @vic_model, cia_model: @cia_model, sid_model: @sid_model, region: @region,
                     ram_expansion: @ram_expansion)
      end

      def ==(other)
        other.is_a?(Setup) && vic_model == other.vic_model && cia_model == other.cia_model &&
          sid_model == other.sid_model && region == other.region && ram_expansion == other.ram_expansion
      end

      def to_s
        parts = [@vic_model, @cia_model, @sid_model, @region.name]
        parts << @ram_expansion if @ram_expansion
        parts.join(", ")
      end
    end
  end
end
