# frozen_string_literal: true

module Badline
  class CPU < Cycleable
    STATUS_FLAGS = [:carry, :zero, :interrupt, :decimal, :break, 1,
                    :overflow, :negative].freeze

    class InvalidOpcodeError < StandardError; end
    include IntegerHelper
    include InstructionSet
    include Interrupts
    include Traps

    attr_reader :memory, :instructions, :boundary_crossed
    attr_accessor :program_counter, :stack_pointer, :status, :a, :x, :y,
                  :nmi, :irq

    def initialize(memory = nil, debug: false)
      @debug = debug
      @memory = memory || Memory.new
      @status = Status.new(STATUS_FLAGS, value: 0b00100000)
      reset_registers

      @nmi = @irq = false
      @irq_sample = @irq_pending = false
      @nmi_sample = @nmi_pending = false
      @skip_poll = false

      @instructions = 0
      @traps = nil
      super()
    end

    def reset!
      status.interrupt = true
      reset_registers
    end

    def p
      status.value
    end

    def p=(new_value)
      status.value = new_value
    end

    def step!
      @loop.resume unless @instruction || @interrupt
      cycle! while @instruction || @interrupt
    end

    def inspect
      "Cycles: #{@cycles}, PC: #{format16(program_counter)}, " \
        "SP: #{format8(stack_pointer)}, A: #{format8(a)}, X: #{format8(x)}, " \
        "Y: #{format8(y)}, P: #{format8(p)}"
    end

    private

    def extra_cycle(instruction)
      return cycle unless instruction.boundary_cycle?

      boundary_crossed && cycle
    end

    def read_byte(addr)
      cycle { @memory.peek(addr) }
    end

    def read_word(addr)
      uint16(read_byte(addr),
             read_byte((addr + 1) & 0xffff))
    end

    def read_zeropage_word(addr)
      uint16(read_byte(addr & 0xff),
             read_byte((addr + 1) & 0xff))
    end

    def read_instruction
      Instruction.find(@memory.peek(@program_counter))
    end

    def read_operand(instruction)
      return nil unless instruction.operand?
      # JSR fetches its operand high byte late (see Stack#jsr).
      return read_byte(program_counter) if instruction.name == :jsr
      return read_word(program_counter) if instruction.operand_length == 2

      read_byte(program_counter)
    end

    def reset_registers
      # The program counter is initialized from the reset vector
      @program_counter = @memory.peek16(0xfffc)
      # Stack pointer starts at 0x01ff and grows down
      @stack_pointer = 0xff
      @a = @x = @y = 0x0
    end

    def read_address(instruction, operand)
      case instruction.addressing_mode
      when :implied, :immediate
        nil
      when :accumulator
        :accumulator
      when :relative
        (@program_counter + signed_int8(operand) + 1) & 0xffff
      when :zeropage, :absolute
        operand
      when :zeropage_x
        cycle { (operand + @x) & 0xff }
      when :zeropage_y
        cycle { (operand + @y) & 0xff }
      when :absolute_x
        # Do an extra cycle if page boundary is crossed
        @boundary_crossed = high_byte(operand + @x) != high_byte(operand)
        extra_cycle(instruction)
        (operand + @x) & 0xffff
      when :absolute_y
        @boundary_crossed = high_byte(operand + @y) != high_byte(operand)
        # Do an extra cycle if page boundary is crossed
        extra_cycle(instruction)
        (operand + @y) & 0xffff
      when :indirect
        # This is only used for JMP. There's no carry associated, so an
        # indirect jump to $30FF will wrap around on the same page and read
        # from [0x30ff, 0x3000].
        uint16(
          read_byte(operand),
          read_byte(uint16(
                      (low_byte(operand) + 1) & 0xff, # Wrap around low byte
                      high_byte(operand)
                    ))
        )
      when :indirect_x
        cycle
        read_zeropage_word(operand + @x)
      when :indirect_y
        value = read_zeropage_word(operand)
        @boundary_crossed = ((value & 0xff) + y) > 0xff
        # Do an extra cycle if page boundary is crossed
        extra_cycle(instruction)
        (value + y) & 0xffff
      end
    end

    def realize_value(instruction, operand, address)
      case instruction.addressing_mode
      when :implied
        raise "Implied value can't be realized"
      when :accumulator
        @a
      when :immediate
        operand
      else
        read_byte(address)
      end
    end

    def stack_address(offset = 0)
      uint16((stack_pointer + offset) & 0xff, 0x01)
    end

    def log(instruction, operand, address)
      return unless @debug

      pc = (@program_counter - 1) - instruction.operand_length
      puts(
        "#{@cycles}: " \
        "PC: #{pc.to_s(16)} - " \
        "#{@instruction.name.upcase} #{@instruction.addressing_mode} " \
        "Operand: #{operand.inspect} Address: #{address.inspect}"
      )
    end

    def main_loop
      irq_pending = @irq_pending
      nmi_pending = @nmi_pending
      poll
      if nmi_pending || irq_pending
        service_interrupt(nmi_pending)
      else
        run_traps
        @boundary_crossed = false
        @instruction = read_instruction
        raise InvalidOpcodeError unless @instruction

        @program_counter = (@program_counter + 1) & 0xffff
        @cycles += 1

        @operand = operand = read_operand(@instruction)
        @address = address = read_address(@instruction, operand)

        @program_counter = (@program_counter + @instruction.operand_length) &
                           0xffff

        log(@instruction, operand, address)

        # Run the instruction; :lazy realizes the value through #resolve
        send(@instruction.name, address, :lazy)

        @instructions += 1
        @instruction = nil
      end
      Fiber.yield
    end

    def write_byte(addr, value)
      if addr == :accumulator
        @a = value
      else
        cycle(write: true) { @memory.poke(addr, value) }
      end
    end
  end
end
