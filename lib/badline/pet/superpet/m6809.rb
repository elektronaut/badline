# frozen_string_literal: true

module Badline
  class PET
    class SuperPET < PET
      # The board's 6809E, on the PET's bus, as the 6502 is. A trap
      # installed on an address runs as the 6809 is about to fetch an
      # opcode there, and may move the PC on.
      class M6809
        include Chips::M6809::Core

        def initialize(bus)
          super
          @traps = nil
        end

        def install_trap(addr, &handler)
          (@traps ||= {})[addr] = handler
        end

        def remove_trap(addr)
          @traps&.delete(addr)
        end

        def cycle!
          @traps[@pc]&.call if @traps && boundary?
          super
        end
      end
    end
  end
end
