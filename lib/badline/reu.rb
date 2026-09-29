# frozen_string_literal: true

require "badline/reu/ram"
require "badline/reu/dma"
require "badline/reu/trigger"

module Badline
  # A RAM Expansion Unit: the Commodore 1700 (128K), 1764 (256K) and 1750
  # (512K), and the bigger units built around the same REC chip, such as
  # the CMD 1750XL, up to 16M. The REC's registers sit in I/O 2, at
  # $DF00-$DF0A, mirrored every 32 bytes up to $DFFF, and it moves bytes
  # between the C64 and its RAM by DMA, one a cycle, with the CPU held off
  # the bus.
  #
  # A command with the execute bit set asks for the bus, which the REC gets
  # on the CPU's next read cycle with BA high. With bit 4 clear it arms the
  # REC instead, and the next write to $FF00 asks for the bus. Computer
  # clocks the transfer through #dma_cycle!.
  class REU
    SIZES_KB = [128, 256, 512, 1024, 2048, 4096, 8192, 16_384].freeze

    # Register offsets.
    STATUS = 0x00
    COMMAND = 0x01
    C64_LOW = 0x02
    C64_HIGH = 0x03
    REU_LOW = 0x04
    REU_HIGH = 0x05
    BANK = 0x06
    LENGTH_LOW = 0x07
    LENGTH_HIGH = 0x08
    INTERRUPT = 0x09
    CONTROL = 0x0a
    REGISTERS = 0x0b

    # Status bits. Reading the register clears the top three.
    CHIPS_256K = 0x10
    VERIFY_ERROR = 0x20
    END_OF_BLOCK = 0x40
    INTERRUPT_PENDING = 0x80

    # Command bits.
    EXECUTE = 0x80
    AUTOLOAD = 0x20
    FF00_DISABLED = 0x10
    TRANSFER_TYPE = 0x03

    # Interrupt mask bits, and the unused ones, which read as 1.
    IRQ_ENABLED = 0x80
    IRQ_END_OF_BLOCK = 0x40
    IRQ_VERIFY = 0x20
    IRQ_UNUSED = 0x1f

    # Address control bits, and the unused ones, which read as 1.
    FIX_C64 = 0x80
    FIX_REU = 0x40
    CONTROL_UNUSED = 0x3f

    # The bank register's top bits, which always read as 1. A REC of 512K
    # or less doesn't have them at all.
    BANK_UNUSED = 0xf8

    # DMA states.
    IDLE = 0
    REQUESTED = 1
    RUNNING = 2

    attr_reader :trigger

    # bus is the bus the REC reaches C64 memory through, and vic the VIC,
    # whose phi1 fetch is left on the bus when the registers are read
    # during a transfer.
    def initialize(size_kb, bus:, vic:)
      raise ArgumentError, "No #{size_kb}K REU. Pick one of #{SIZES_KB.join(', ')}." unless SIZES_KB.include?(size_kb)

      size = size_kb * 1024
      # The 1700's REC wraps its addresses at 128K, the others at 512K.
      wrap = size_kb == 128 ? 0x20000 : 0x80000
      @store_mask = [size, wrap].max - 1
      @bank_unused = size > wrap ? 0 : BANK_UNUSED
      @status_preset = size_kb == 128 ? 0 : CHIPS_256K
      @ram = RAM.new(size, wrap)
      @dma = DMA.new(@ram, wrap, bus)
      @trigger = Trigger.new(self)
      @vic = vic
      @on_irq_change = nil
      @on_dma = nil
      @irq = false
      reset!
    end

    def on_irq_change(&block)
      @on_irq_change = block
    end

    # Called when the REC asks for the bus.
    def on_dma(&block)
      @on_dma = block
    end

    def irq? = @irq

    # True from the moment the REC asks for the bus until it hands it back.
    def dma? = @state != IDLE

    def reset!
      @status = @status_preset
      @command = FF00_DISABLED
      @c64_address = @c64_shadow = 0
      @reu_address = @reu_shadow = 0
      @bank = @bank_shadow = @bank_unused
      @length = @length_shadow = 0xffff
      @interrupt_mask = IRQ_UNUSED
      @address_control = CONTROL_UNUSED
      @armed = false
      @state = IDLE
      interrupt(false)
    end

    def peek(addr)
      return @vic.phi1_data if @state == RUNNING

      register = addr & 0x1f
      return 0xff if register >= REGISTERS

      value = register_value(register)
      if register == STATUS
        @status &= CHIPS_256K
        interrupt(false)
      end
      value
    end

    def poke(addr, value)
      return if @state == RUNNING

      case addr & 0x1f
      when COMMAND then write_command(value)
      when C64_LOW then @c64_address = @c64_shadow = (@c64_shadow & 0xff00) | value
      when C64_HIGH then @c64_address = @c64_shadow = (@c64_shadow & 0xff) | (value << 8)
      when REU_LOW then @reu_address = @reu_shadow = (@reu_shadow & 0xff00) | value
      when REU_HIGH then @reu_address = @reu_shadow = (@reu_shadow & 0xff) | (value << 8)
      when BANK then @bank = @bank_shadow = value & ~@bank_unused & 0xff
      when LENGTH_LOW then @length = @length_shadow = (@length_shadow & 0xff00) | value
      when LENGTH_HIGH then @length = @length_shadow = (@length_shadow & 0xff) | (value << 8)
      when INTERRUPT then write_interrupt_mask(value)
      when CONTROL then @address_control = value | CONTROL_UNUSED
      end
    end

    # A write to $FF00 asks for the bus if the command register armed the
    # REC.
    def ff00_written
      return unless @armed

      @armed = false
      request
    end

    # Clocks the REC for a cycle, given the VIC's BA line and whether the
    # CPU writes on it. A requested transfer starts on a read cycle with BA
    # high.
    def dma_cycle!(ba_low, cpu_writing)
      if @state == REQUESTED
        return if cpu_writing || ba_low

        start
      end
      @dma.cycle!(ba_low)
      finish unless @dma.holds_bus?
    end

    # Whether the REC held the bus on the last cycle clocked. The CPU has
    # it while the REC waits to start, and from the cycle it hands it back.
    def holds_bus? = @state == RUNNING

    # The REU's RAM, at an address as the REC's registers give it.
    def ram_peek(addr) = @ram.peek(addr)

    def ram_poke(addr, value) = @ram.poke(addr, value)

    private

    def register_value(register)
      case register
      when STATUS then @status
      when COMMAND then @command
      when C64_LOW then @c64_address & 0xff
      when C64_HIGH then @c64_address >> 8
      when REU_LOW then @reu_address & 0xff
      when REU_HIGH then @reu_address >> 8
      when BANK then @bank | BANK_UNUSED
      when LENGTH_LOW then @length & 0xff
      when LENGTH_HIGH then @length >> 8
      when INTERRUPT then @interrupt_mask
      else @address_control
      end
    end

    def write_command(value)
      @command = value
      return if value.nobits?(EXECUTE)

      @armed = value.nobits?(FF00_DISABLED)
      request unless @armed
    end

    # Enabling an interrupt whose condition already stands raises it.
    def write_interrupt_mask(value)
      @interrupt_mask = value | IRQ_UNUSED
      raise_interrupts(@status)
    end

    def raise_interrupts(status)
      return unless (status.anybits?(END_OF_BLOCK) && interrupt_enabled?(IRQ_END_OF_BLOCK)) ||
                    (status.anybits?(VERIFY_ERROR) && interrupt_enabled?(IRQ_VERIFY))

      @status |= INTERRUPT_PENDING
      interrupt(true)
    end

    def interrupt_enabled?(bit)
      @interrupt_mask.allbits?(IRQ_ENABLED | bit)
    end

    def interrupt(level)
      return if @irq == level

      @irq = level
      @on_irq_change&.call(level)
    end

    def request
      @state = REQUESTED
      @on_dma&.call
    end

    def start
      @state = RUNNING
      @dma.start(@command & TRANSFER_TYPE, @c64_address, @reu_address | (@bank << 16), @length, @address_control)
    end

    # The execute bit clears and the $FF00 trigger turns off. Autoload puts
    # the address and length registers back as they were written, and
    # otherwise they are left where the transfer stopped.
    def finish
      @state = IDLE
      @command = (@command & ~EXECUTE & 0xff) | FF00_DISABLED
      result = @dma.result
      @status |= result
      @command.anybits?(AUTOLOAD) ? autoload : store_addresses
      raise_interrupts(result)
    end

    def autoload
      @c64_address = @c64_shadow
      @reu_address = @reu_shadow
      @bank = @bank_shadow
      @length = @length_shadow
    end

    def store_addresses
      @c64_address = @dma.host if @address_control.nobits?(FIX_C64)
      @length = @dma.remaining & 0xffff
      return if @address_control.anybits?(FIX_REU)

      target = @dma.target & @store_mask
      @reu_address = target & 0xffff
      @bank = (target >> 16) & 0xff
    end
  end
end
