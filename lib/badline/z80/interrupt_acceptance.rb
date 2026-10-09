# frozen_string_literal: true

module Badline
  class Z80
    # Taking NMI and INT between instructions. Either wakes a halted CPU,
    # whose program counter already points past the HALT.
    module InterruptAcceptance
      private

      # An opcode fetch whose byte is ignored, a T-state more, and a call
      # to $0066. IFF2 keeps what IFF1 held, for RETN to restore.
      def take_nmi
        @nmi_pending = false
        @halted = false
        @iff1 = false
        @bus.fetch(@pc)
        refresh
        @cycles += 5
        push(@pc)
        @pc = 0x66
        @wz = 0x66
      end

      # The acknowledge cycle, an M1 with two wait states, reads a byte
      # from the device. Mode 0 runs it as an opcode, which is a RST in
      # practice, mode 1 calls $0038, and mode 2 calls through the vector
      # at I and that byte.
      def take_int
        @halted = false
        @f &= ~PF if @after_ld_a_ir
        @iff1 = @iff2 = false
        @after_ld_a_ir = false
        @prefix = 0
        data = @bus.acknowledge
        refresh
        @cycles += 6
        return execute(data) if @im.zero?

        @cycles += 1
        push(@pc)
        @pc = @im == 1 ? 0x38 : read_word((@i << 8) | data)
        @wz = @pc
      end
    end
  end
end
