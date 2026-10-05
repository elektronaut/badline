# frozen_string_literal: true

module Badline
  module Snapshot
    module Vice
      # REU1764 0.0, VICE's module for an REU of any size, which x64sc
      # writes straight after C64CART when the cartridge port lists the
      # REU: the size in K, the sixteen bytes the REC's registers read
      # from $DF00, and the RAM.
      #
      # Written: the registers and the RAM. VICE saves between transfers,
      # so badline's copy of the machine runs a transfer in flight to its
      # end first (Vice.settled).
      #
      # Read: the registers, as the values the counters run from and
      # start from, and the RAM. The status register's interrupt, end of
      # block and fault bits come back with the IRQ line, and a command
      # waiting for a write to $FF00 stays armed.
      module REU1764
        NAME = "REU1764"
        MAJOR = 0
        MINOR = 0
        # C64CART's id for the REU, VICE's CARTRIDGE_REU.
        CARTRIDGE_ID = -105

        module_function

        def export(computer)
          reu = computer.reu
          FieldWriter.new.dword(reu.size_kb).bytes(reu.register_file).bytes(reu.ram_contents)
                     .section(NAME, MAJOR, MINOR)
        end

        def reads?(section) = section.major == MAJOR && section.minor == MINOR

        # The REU's size in K, which builds the machine.
        def size_kb(section)
          size = FieldReader.new(section).dword
          return size if REU::SIZES_KB.include?(size)

          raise FormatError, "#{section}: a #{size}K REU, which badline doesn't build"
        end

        def import(section, computer)
          reu = computer.reu
          fields = FieldReader.new(section)
          fields.skip(4)
          registers = fields.bytes(16)
          reu.restore_ram(fields.string(reu.size_kb * 1024))
          reu.restore_registers(registers)
        end
      end
    end
  end
end
