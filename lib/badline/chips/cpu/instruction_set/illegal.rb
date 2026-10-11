# frozen_string_literal: true

module Badline
  module InstructionSet
    # Illegal opcodes
    module Illegal
      # Combination of AND and LSR.
      #
      # Opcodes:
      #   $4B - immediate - 2 cycles
      def alr(_addr, value)
        @a &= value
        status.carry = @a[0]
        @a = (@a >> 1) & 0xff
        update_number_flags(@a)
      end

      # Combination of AND where carry is set to bit 7 of result.
      #
      # Opcodes:
      #   $0B, $2B - immediate - 2 cycles
      def anc(addr, value)
        self.and(addr, value)
        status.carry = status.negative
      end

      # Unstable instruction. AND's value with A|magic_const and X.
      # Magic constant varies by CPU. A VIC stall between the opcode and
      # operand fetches clears its bits 0 and 4.
      #
      # Opcodes:
      #   $8B - immediate - 2 cycles
      def ane(_addr, value)
        magic_const = stalled_before_this_cycle? ? @ane_constant & 0xee : @ane_constant
        @a = (a | magic_const) & x & value
        update_number_flags(@a)
      end

      # Combination of AND and ROR.
      #
      # Opcodes:
      #   $6B - immediate - 2 cycles
      def arr(_addr, value)
        tmp = a & value
        result = (tmp >> 1) | (status.carry? ? 0x80 : 0)
        status.zero = result.zero?
        status.negative = status.carry

        if status.decimal?
          status.overflow = (result ^ tmp).anybits?(0x40)

          # Low nibble
          result = (result & 0xf0) | ((result + 0x06) & 0x0f) if ((tmp & 0x0f) + (tmp & 0x01)) > 0x05

          # High nibble + carry
          if ((tmp & 0xf0) + (tmp & 0x10)) > 0x50
            result = (result & 0x0f) | ((result + 0x60) & 0xf0)
            status.carry = true
          else
            status.carry = false
          end
        else
          status.carry = tmp[7] == 1
          status.overflow = tmp[7] ^ tmp[6]
        end

        @a = result
      end

      # Combination of DEC and CMP operations.
      #
      # Opcodes:
      #   $C3 - indirect_x - 8 cycles
      #   $C7 - zeropage   - 5 cycles
      #   $CF - absolute   - 6 cycles
      #   $D3 - indirect_y - 8 cycles
      #   $D7 - zeropage_x - 6 cycles
      #   $DB - absolute_y - 7 cycles
      #   $DF - absolute_x - 7 cycles
      def dcp(addr, value)
        cmp(addr, dec(addr, value))
      end

      # Combination of INC and SBC operations.
      #
      # Opcodes:
      #   $E3 - indirect_x - 8 cycles
      #   $E7 - zeropage   - 5 cycles
      #   $EF - absolute   - 6 cycles
      #   $F3 - indirect_y - 8 cycles
      #   $F7 - zeropage_x - 6 cycles
      #   $FB - absolute_y - 7 cycles
      #   $FF - absolute_x - 7 cycles
      def isc(addr, value)
        sbc(addr, inc(addr, value))
      end

      # Loads A and S with value AND stack pointer.
      #
      # Opcodes:
      #   $BB - absolute_y - 4 cycles
      def las(_addr, value)
        @a = @x = @stack_pointer = value & stack_pointer
        update_number_flags(@a)
      end

      # Combination of LDA and LDX with same value.
      #
      # Opcodes:
      #   $A3 - indirect_x - 6 cycles
      #   $A7 - zeropage   - 3 cycles
      #   $AF - absolute   - 4 cycles
      #   $B3 - indirect_y - 5+ cycles
      #   $B7 - zeropage_y - 4 cycles
      #   $BF - absolute_y - 4+ cycles
      def lax(_addr, value)
        @a = @x = value

        update_number_flags(@a)
      end

      # Unstable immediate form of LAX. Loads A and X with
      # (A | magic_const) AND value. Magic constant varies by CPU.
      #
      # Opcodes:
      #   $AB - immediate - 2 cycles
      def lxa(_addr, value)
        magic_const = 0xee
        @a = @x = (a | magic_const) & value
        update_number_flags(@a)
      end

      # Special no-operation instruction that does not consume a CPU cycle,
      # unlike the standard NOP. Used by some illegal opcodes.
      #
      # Opcodes:
      #   $80, $82, $89, $C2, $E2 - immediate - 2 cycles
      def nop_nocycle(_addr, _value); end

      # Combination of ROL and AND operations.
      #
      # Opcodes:
      #   $23 - indirect_x - 8 cycles
      #   $27 - zeropage   - 5 cycles
      #   $2F - absolute   - 6 cycles
      #   $33 - indirect_y - 8 cycles
      #   $37 - zeropage_x - 6 cycles
      #   $3B - absolute_y - 7 cycles
      #   $3F - absolute_x - 7 cycles
      def rla(addr, value)
        self.and(addr, rol(addr, value))
      end

      # Combination of ROR and ADC operations.
      #
      # Opcodes:
      #   $63 - indirect_x - 8 cycles
      #   $67 - zeropage   - 5 cycles
      #   $6F - absolute   - 6 cycles
      #   $73 - indirect_y - 8 cycles
      #   $77 - zeropage_x - 6 cycles
      #   $7B - absolute_y - 7 cycles
      #   $7F - absolute_x - 7 cycles
      def rra(addr, value)
        adc(addr, ror(addr, value))
      end

      # Store A AND X.
      #
      # Opcodes:
      #   $83 - indirect_x - 6 cycles
      #   $87 - zeropage   - 3 cycles
      #   $8F - absolute   - 4 cycles
      #   $97 - zeropage_y - 4 cycles
      def sax(addr, _value)
        write_byte(addr, @a & @x)
      end

      # AND X register with accumulator and subtract value.
      #
      # Opcodes:
      #   $CB - immediate - 2 cycles
      def sbx(_addr, value)
        result = (@x & @a) - value
        status.carry = result >= 0
        @x = result & 0xff
        update_number_flags(@x)
      end

      # Stores A AND X AND (high byte of base address + 1) at addr.
      #
      # Opcodes:
      #   $93 - indirect_y - 6 cycles
      #   $9F - absolute_y - 5 cycles
      def sha(addr, _value)
        store_high_and(a & x, addr)
      end

      # Stores X AND (high byte of base address + 1) at addr.
      #
      # Opcodes:
      #   $9E - absolute_y - 5 cycles
      def shx(addr, _value)
        store_high_and(x, addr)
      end

      # Stores Y AND (high byte of base address + 1) at addr.
      #
      # Opcodes:
      #   $9C - absolute_x - 5 cycles
      def shy(addr, _value)
        store_high_and(y, addr)
      end

      # Combination of ASL and ORA operations.
      #
      # Opcodes:
      #   $03 - indirect_x - 8 cycles
      #   $07 - zeropage   - 5 cycles
      #   $0F - absolute   - 6 cycles
      #   $13 - indirect_y - 8 cycles
      #   $17 - zeropage_x - 6 cycles
      #   $1B - absolute_y - 7 cycles
      #   $1F - absolute_x - 7 cycles
      def slo(addr, value)
        ora(addr, asl(addr, value))
      end

      # Combination of LSR and EOR operations.
      #
      # Opcodes:
      #   $43 - indirect_x - 8 cycles
      #   $47 - zeropage   - 5 cycles
      #   $4F - absolute   - 6 cycles
      #   $53 - indirect_y - 8 cycles
      #   $57 - zeropage_x - 6 cycles
      #   $5B - absolute_y - 7 cycles
      #   $5F - absolute_x - 7 cycles
      def sre(addr, value)
        eor(addr, lsr(addr, value))
      end

      # Stores A AND X in SP, then stores SP AND (high byte of base + 1) at
      # addr.
      #
      # Opcodes:
      #   $9B - absolute_y - 5 cycles
      def tas(addr, _value)
        @stack_pointer = @a & @x
        store_high_and(stack_pointer, addr)
      end

      private

      # A VIC stall right before the dummy read, the second-to-last cycle,
      # drops the & (H+1) from the stored value but not from the high byte
      # of a page-crossing target.
      def store_high_and(register, addr)
        base_high = if boundary_crossed
                      (high_byte(addr) - 1) & 0xff
                    else
                      high_byte(addr)
                    end
        result = register & ((base_high + 1) & 0xff)
        target = boundary_crossed ? uint16(low_byte(addr), result) : addr
        write_byte(target, stalled_before_previous_cycle? ? register : result)
      end
    end
  end
end
