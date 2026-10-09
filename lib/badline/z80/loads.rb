# frozen_string_literal: true

module Badline
  class Z80
    # Loads, PUSH, and IN and OUT through a port A and n address. The loads
    # through a pointer leave the address after it in WZ, or for a store of
    # A, A and the low byte of that address.
    module Loads
      private

      # LD r,r' with (HL) as index 6.
      def load_register(target, source)
        if source == 6
          set_plain_register(target, read_byte(operand_address))
        elsif target == 6
          write_byte(operand_address, plain_register(source))
        else
          set_register(target, register(source))
        end
      end

      # LD r,n, and LD (IX+d),n, which reads n while it adds d.
      def load_immediate(index)
        return set_register(index, fetch_byte) unless index == 6
        return write_byte(hl, fetch_byte) if @prefix.zero?

        displaced
        value = fetch_byte
        @cycles += 2
        write_byte(@wz, value)
      end

      def indirect_load(row)
        case row
        when 0 then store_a(bc)
        when 1 then load_a(bc)
        when 2 then store_a(de)
        when 3 then load_a(de)
        when 4 then store_word(hl_or_index)
        when 5 then self.hl_or_index = load_word
        when 6 then store_a(fetch_word)
        else load_a(fetch_word)
        end
      end

      def load_a(address)
        @a = read_byte(address)
        @wz = (address + 1) & 0xffff
      end

      def store_a(address)
        write_byte(address, @a)
        @wz = (@a << 8) | ((address + 1) & 0xff)
      end

      def store_word(value)
        address = fetch_word
        write_word(address, value)
        @wz = (address + 1) & 0xffff
      end

      def load_word
        address = fetch_word
        @wz = (address + 1) & 0xffff
        read_word(address)
      end

      def push_pair(index)
        @cycles += 1
        push(stack_pair(index))
      end

      # RET, EXX, JP (HL) and LD SP,HL.
      def stack_and_exchange(index)
        case index
        when 0 then return_from_call
        when 1 then exchange_alternates
        when 2 then @pc = hl_or_index
        else
          @cycles += 2
          @sp = hl_or_index
        end
      end

      def output_immediate
        port = (@a << 8) | fetch_byte
        output(port, @a)
        @wz = (port & 0xff00) | ((port + 1) & 0xff)
      end

      def input_immediate
        port = (@a << 8) | fetch_byte
        @wz = (port + 1) & 0xffff
        @a = input(port)
      end
    end
  end
end
