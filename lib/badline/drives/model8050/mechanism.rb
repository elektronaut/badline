# frozen_string_literal: true

module Badline
  module Drives
    class Model8050
      # The unit's two drives as the floppy controller sees them through
      # the VIA and the 6530 (schematic 8050001, sheets 2 and 3), with no
      # disk in either: no SYNC, no byte ready, and the data lines high.
      #
      # The 6530's port B reads write protect on PB3, low while the disk
      # can be written; the drive type on PB4, high for the 8050's format
      # ("2C"); and the sides on PB6, low for two, which jumper E3 grounds
      # on the 8250.
      class Mechanism
        WRITE_PROTECT = 0x08
        ONE_SIDE = 0x40

        attr_reader :sides

        def initialize(sides:)
          @sides = sides
          @so_pending = false
        end

        def cycle! = nil

        # Whether byte ready pulses the controller's SO pin this cycle,
        # which takes the pulse.
        def take_so
          so = @so_pending
          @so_pending = false
          so
        end

        # The byte the GCR ROM decodes off the shift register, on VIA port A.
        def data_in = 0xff

        # Whether ten one bits sit in the shift register.
        def sync? = false

        # The 6530's port B inputs.
        def status_lines
          lines = 0xff & ~WRITE_PROTECT
          @sides == 2 ? lines & ~ONE_SIDE : lines
        end
      end

      # VIA port A reads the decoded byte, and PB7 SYNC, low while the
      # shift register holds a sync.
      class ReadLines
        def initialize(mechanism)
          @mechanism = mechanism
        end

        def read_a(_lines) = @mechanism.data_in

        def read_b(_lines) = @mechanism.sync? ? 0x7f : 0xff
      end

      # The 6530's port B inputs from the drives.
      class StatusLines
        def initialize(mechanism)
          @mechanism = mechanism
        end

        def read_a(_lines) = 0xff

        def read_b(_lines) = @mechanism.status_lines
      end
    end
  end
end
