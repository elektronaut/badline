# frozen_string_literal: true

require "badline/chips/ted"
require "badline/chips/tia"
require "badline/plus4/model"
require "badline/plus4/cpu"
require "badline/plus4/cpu_port"
require "badline/plus4/keyboard_port"
require "badline/plus4/user_port"
require "badline/plus4/acia"
require "badline/plus4/bus"

module Badline
  # The Commodore 264 series: the Plus/4, the C16 and the C116. A 7501 on
  # the TED's clock, which runs it once or twice a TED cycle (Chips::TED's
  # Beam), the TED and, on the Plus/4, a 6551 ACIA and the user port's
  # 6529. Only the TED pulls IRQ, and nothing pulls NMI, which the 7501
  # doesn't have.
  #
  # It runs headless only: the TED paints no picture yet, and nothing
  # attaches media.
  class Plus4
    include IntegerHelper
    include Machine::KeyboardBuffer
    include Machine::Clocking

    # The cycle by which the KERNAL has booted and BASIC printed READY,
    # with a margin, in TED cycles. READY is up by about 116,000 on a PAL
    # Plus/4, 126,000 on an NTSC one and sooner on a C16.
    INIT_THRESHOLD = 200_000

    attr_reader :model, :bus, :cpu, :ted, :port, :keyboard, :keyboard_port, :acia, :user_port, :datasette, :tias,
                :iec_bus, :cycles, :ram_kb

    def family = :plus4

    def init_threshold = INIT_THRESHOLD

    def ram = @bus.ram

    # Reads and writes memory as the CPU sees it, through the bus.
    def peek(addr) = @bus.peek(addr)

    def poke(addr, value) = @bus.poke(addr, value)

    # +model+ names one of Model::ALL, or c116 for the C16, and +ram+ the
    # RAM in K, one of Model::RAM_SIZES, when not the model's own. +tcbm+
    # plugs in a 1551's TCBM interface, the TIAs at $FEC0-$FEFF, with no
    # drive answering on the other side.
    def initialize(model: "plus4", ram: nil, tcbm: false, debug: false)
      @model = Model.named(model)
      @ram_kb = ram || @model.ram_kb
      raise ArgumentError, "no Plus/4 RAM size of #{@ram_kb}K" unless Model::RAM_SIZES.include?(@ram_kb)

      @ted = Chips::TED.new(@model.ted)
      @keyboard = Input::Keyboard.new(matrix: KeyboardPort::MATRIX)
      @keyboard_port = KeyboardPort.new(@keyboard)
      @ted.keyboard_port = @keyboard_port
      @iec_bus = Drives::SerialBus.new
      @datasette = Drives::Datasette.new(level: true)
      @port = CPUPort.new(serial_bus: @iec_bus, datasette: @datasette)
      plus4_parts = @model.plus4_parts
      @acia = plus4_parts ? ACIA.new : nil
      @user_port = plus4_parts ? UserPort.new(@datasette) : nil
      io = Bus::IOPage.new(keyboard_port: @keyboard_port, acia: @acia, user_port: @user_port)
      @bus = Bus.new(ted: @ted, port: @port, io:, model: @model, ram_kb: @ram_kb)
      @tias = tcbm ? [Chips::TIA.new, Chips::TIA.new] : []
      @bus.plug_tcbm(drive8: @tias[0], drive9: @tias[1]) if tcbm
      @cpu = CPU.new(@bus, debug:)
      @cycles = 0
      @init_handlers = []
      @pending_keys = nil
    end

    # One TED cycle: the TED moves on and decides the CPU's clock, then the
    # CPU runs its cycles in it, none while the TED holds the bus.
    def cycle!
      handle_init if @cycles == INIT_THRESHOLD
      feed_keyboard if @pending_keys

      ted = @ted
      ted.cycle!
      @datasette.cycle!
      @cpu.irq = ted.irq?
      slots = ted.cpu_slots
      if slots.zero?
        @cpu.stall!
      else
        clock_cpu(ted)
        clock_cpu(ted) if slots == 2
      end

      @cycles += 1
    end

    # The RESET line: the CPU, the port, the 6529s, the ACIA, the bank
    # latch and ROM selection. The TED has no reset pin.
    def reset!
      @port.reset!
      @keyboard_port.reset!
      @user_port&.reset!
      @acia&.reset!
      @tias.each(&:reset!)
      @bus.reset!
      @cpu.reset!
    end

    # Switches the machine off and on: RAM and the TED start from their
    # power-on state, and the RES line resets everything else.
    def power_cycle!
      @bus.power_on!
      @ted.power_on!
      reset!
    end

    # Calls the block with the exit code a VICE testprog writes to $FDCF.
    def install_debug_register(&) = @bus.install_debug_register(&)

    # Puts a cartridge's ROM chips in cartridge 1's slots (Bus#attach_cartridge)
    # and switches the machine off and on, as a cartridge goes in with the
    # power off. The KERNAL starts it at reset when it signs itself with CBM
    # at $8007.
    def attach_cartridge(chips)
      @bus.attach_cartridge(chips)
      power_cycle!
    end

    # Stores a PRG's bytes from its load address on, into RAM, and returns
    # that address.
    def load_prg(data)
      load_addr = uint16(data[0], data[1])
      bytes = data[2..] || []
      bytes = bytes[0, 0x10000 - load_addr] if load_addr + bytes.length > 0x10000
      bytes.each_with_index { |byte, i| @bus.ram_view.poke(load_addr + i, byte) }
      load_addr
    end

    private

    # The 264 KERNAL's keyboard buffer.
    def keyboard_buffer = Machine::KeyboardBuffer::PLUS4_LAYOUT

    # BA stops the CPU at a read, and a write goes ahead.
    def clock_cpu(ted)
      ted.ba_low? && !@cpu.pending_write? ? @cpu.stall! : @cpu.cycle!
    end
  end
end
