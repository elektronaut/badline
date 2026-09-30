# frozen_string_literal: true

require "badline/reu/ram"
require "badline/reu/dma"
require "badline/reu/trigger"
require "badline/reu/saved_state"

module Badline
  # A RAM Expansion Unit: the Commodore 1700 (128K), 1764 (256K) and 1750
  # (512K), and the bigger units built around the same 8726 RAM Expansion
  # Controller (REC), such as the CMD 1750XL, up to 16M.
  #
  # The REC's eleven registers sit in I/O 2 from $DF00, repeated every 32
  # bytes up to $DFFF, as the 1764 and 1750 manuals map them. It moves
  # bytes between the C64 and its RAM by DMA, one bus cycle each, with the
  # CPU held off the bus. A command with the execute bit set starts a
  # transfer, or with bit 4 clear arms the REC to start one on the next
  # write to $FF00, so a program can bank the ROMs out first. A transfer
  # waits for the CPU's next read cycle with BA high, and Computer then
  # clocks it through #dma_cycle! until it hands the bus back.
  class REU
    include SavedState

    SIZES_KB = [128, 256, 512, 1024, 2048, 4096, 8192, 16_384].freeze

    # The registers, by offset.
    STATUS = 0x00
    COMMAND = 0x01
    C64_LOW = 0x02
    C64_HIGH = 0x03
    EXPANSION_LOW = 0x04
    EXPANSION_HIGH = 0x05
    EXPANSION_BANK = 0x06
    LENGTH_LOW = 0x07
    LENGTH_HIGH = 0x08
    INTERRUPT_MASK = 0x09
    ADDRESS_CONTROL = 0x0a

    # Status: an interrupt is pending, the block ended, a verify found a
    # difference (the manual's fault bit), and the unit is built from 256K
    # chips, which only the 1700 isn't. Reading the status clears the top
    # three.
    INTERRUPT_PENDING = 0x80
    END_OF_BLOCK = 0x40
    FAULT = 0x20
    CHIPS_256K = 0x10

    # Command: execute, reload the registers after the transfer, don't wait
    # for $FF00, and the transfer type in the bottom two bits.
    EXECUTE = 0x80
    AUTOLOAD = 0x20
    NO_FF00_TRIGGER = 0x10
    TRANSFER_TYPE = 0x03

    # Interrupt mask: interrupts on at all, then on the end of a block and
    # on a fault. The low five bits aren't there and read as 1.
    INTERRUPTS_ON = 0x80
    INTERRUPT_ON_END = 0x40
    INTERRUPT_ON_FAULT = 0x20

    # Address control: hold the C64 address or the expansion address where
    # it is. The low six bits aren't there and read as 1.
    FIX_C64 = 0x80
    FIX_EXPANSION = 0x40

    # The REC's bank register has three bits, and the other five read as
    # 1. A unit past 512K latches all eight onto its own address lines.
    BANK_STUCK = 0xf8

    attr_reader :trigger

    # bus is the bus the REC reaches C64 memory through, and vic the VIC,
    # whose phi1 fetch is what a register read finds on the bus during a
    # transfer.
    def initialize(size_kb, bus:, vic:)
      raise ArgumentError, "No #{size_kb}K REU. Pick one of #{SIZES_KB.join(', ')}." unless SIZES_KB.include?(size_kb)

      # The 1700's REC counts 17 address bits, the others' 19.
      span = size_kb == 128 ? 0x20000 : 0x80000
      @size_kb = size_kb
      size = size_kb * 1024
      @address_mask = [size, span].max - 1
      @bank_bits = size > span ? 0xff : 0x07
      @chips = size_kb == 128 ? 0 : CHIPS_256K
      @ram = RAM.new(size, span)
      @dma = DMA.new(@ram, span, bus)
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

    # From the moment the REC asks for the bus until it hands it back.
    def dma? = @requested || @running

    # Whether the REC ran a transfer on the last cycle clocked, which it
    # goes on doing until the cycle it lets go of the bus.
    def holds_bus? = @running

    def reset!
      @status = @chips
      @command = NO_FF00_TRIGGER
      @c64 = @c64_start = 0
      @expansion = @expansion_start = 0
      @bank = @bank_start = 0
      @length = @length_start = 0xffff
      @interrupt_mask = 0x1f
      @address_control = 0x3f
      @armed = @requested = @running = false
      interrupt(false)
    end

    def peek(addr)
      return @vic.phi1_data if @running

      register = addr & 0x1f
      value = register_value(register)
      read_status if register == STATUS
      value
    end

    def poke(addr, value)
      return if @running

      register = addr & 0x1f
      case register
      when COMMAND then write_command(value)
      when C64_LOW, C64_HIGH then @c64 = @c64_start = with_byte(@c64_start, value, register == C64_HIGH)
      when EXPANSION_LOW, EXPANSION_HIGH
        @expansion = @expansion_start = with_byte(@expansion_start, value, register == EXPANSION_HIGH)
      when EXPANSION_BANK then @bank = @bank_start = value & @bank_bits
      when LENGTH_LOW, LENGTH_HIGH
        @length = @length_start = with_byte(@length_start, value, register == LENGTH_HIGH)
      when INTERRUPT_MASK then write_interrupt_mask(value)
      when ADDRESS_CONTROL then @address_control = value | 0x3f
      end
    end

    # A write to $FF00 starts the transfer the command register armed.
    def ff00_written
      return unless @armed

      @armed = false
      request_bus
    end

    # Clocks the REC for a cycle, given the VIC's BA line. A requested
    # transfer starts on the first cycle with BA high as the REC sees it,
    # even one the CPU writes on. Pinned by REU/rmw-trigger.
    def dma_cycle!(ba_low)
      late = ba_low && @vic.reu_ba_late?
      if @requested
        return if ba_low && !late

        start_transfer
      end
      @dma.cycle!(ba_low, late, ba_low && @vic.reu_ba_handed_on?)
      end_transfer unless @dma.holds_bus?
    end

    # The REU's RAM, at an address as the REC's registers give it.
    def ram_peek(addr) = @ram.peek(addr)

    def ram_poke(addr, value) = @ram.poke(addr, value)

    private

    def register_value(register)
      case register
      when STATUS then @status
      when COMMAND then @command
      when C64_LOW then @c64 & 0xff
      when C64_HIGH then @c64 >> 8
      when EXPANSION_LOW then @expansion & 0xff
      when EXPANSION_HIGH then @expansion >> 8
      when EXPANSION_BANK then @bank | BANK_STUCK
      when LENGTH_LOW then @length & 0xff
      when LENGTH_HIGH then @length >> 8
      when INTERRUPT_MASK then @interrupt_mask
      when ADDRESS_CONTROL then @address_control
      else 0xff
      end
    end

    def read_status
      @status &= CHIPS_256K
      interrupt(false)
    end

    # Writing either byte of an address or the length sets the value the
    # transfer starts from, and puts the counter back to it.
    def with_byte(word, value, high)
      high ? (word & 0x00ff) | (value << 8) : (word & 0xff00) | value
    end

    def write_command(value)
      @command = value
      return if value.nobits?(EXECUTE)

      @armed = value.nobits?(NO_FF00_TRIGGER)
      request_bus unless @armed
    end

    # An interrupt enabled over a block that already ended, or a fault
    # already found, fires at once.
    def write_interrupt_mask(value)
      @interrupt_mask = value | 0x1f
      interrupt_on(@status)
    end

    def interrupt_on(events)
      return unless @interrupt_mask.anybits?(INTERRUPTS_ON)
      return unless (events.anybits?(END_OF_BLOCK) && @interrupt_mask.anybits?(INTERRUPT_ON_END)) ||
                    (events.anybits?(FAULT) && @interrupt_mask.anybits?(INTERRUPT_ON_FAULT))

      @status |= INTERRUPT_PENDING
      interrupt(true)
    end

    def interrupt(level)
      return if @irq == level

      @irq = level
      @on_irq_change&.call(level)
    end

    def request_bus
      @requested = true
      @on_dma&.call
    end

    def start_transfer
      @requested = false
      @running = true
      @dma.start(@command & TRANSFER_TYPE, @c64, @expansion | (@bank << 16), @length, @address_control)
    end

    # The execute bit drops and the $FF00 trigger turns off. With autoload
    # the addresses and the length go back to where the transfer started,
    # and otherwise they stay where it stopped.
    def end_transfer
      @running = false
      @command = (@command & ~EXECUTE & 0xff) | NO_FF00_TRIGGER
      events = @dma.events
      @status |= events
      @command.anybits?(AUTOLOAD) ? reload : keep_counters
      interrupt_on(events)
    end

    def reload
      @c64 = @c64_start
      @expansion = @expansion_start
      @bank = @bank_start
      @length = @length_start
    end

    def keep_counters
      @c64 = @dma.c64 if @address_control.nobits?(FIX_C64)
      @length = @dma.length & 0xffff
      return if @address_control.anybits?(FIX_EXPANSION)

      address = @dma.expansion & @address_mask
      @expansion = address & 0xffff
      @bank = (address >> 16) & 0xff
    end
  end
end
