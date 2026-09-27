# frozen_string_literal: true

module Badline
  module Snapshot
    module Vice
      # SID 1.5, the module every VICE SID engine writes: the number of
      # extra SIDs, whether sound is on, the engine, the model and the 32
      # registers as last written. The engine's own state goes in
      # SIDEXTENDED, which is reSID's and badline doesn't read.
      #
      # Read: the registers are written to the SID in order, so the voices
      # start again from the gates as they stand, with their envelopes and
      # oscillators from zero.
      module SIDRegisters
        NAME = "SID"
        MAJOR = 1
        MINOR = 5
        RESID = 1
        MODELS = %i[mos6581 mos8580].freeze

        module_function

        def export(computer)
          sid = computer.sid
          fields = FieldWriter.new.byte(0).byte(1).byte(RESID).byte(MODELS.index(sid.model))
          fields.bytes(Array.new(0x20) { |reg| sid.register(reg) })
          fields.section(NAME, MAJOR, MINOR)
        end

        def engine(section) = FieldReader.new(section).skip(2).byte

        def model(section)
          MODELS.fetch(FieldReader.new(section).skip(3).byte, :mos6581)
        end

        def import(section, computer)
          raise FormatError, "SID #{section.version} is older than badline reads" if section.minor < 4

          registers = FieldReader.new(section).skip(4).bytes(0x20)
          registers.first(0x19).each_with_index { |value, reg| computer.sid.poke(0xd400 + reg, value) }
        end
      end
    end
  end
end
