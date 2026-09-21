# frozen_string_literal: true

require "forwardable"

module Badline
  class Computer
    include IntegerHelper
    include KeyboardBuffer
    extend Forwardable

    attr_reader :address_bus, :cpu, :cycles

    def_delegators :address_bus, :vic, :cia1, :cia2, :sid, :ram, :keyboard, :joystick2,
                   :install_debug_register

    def initialize(debug: false)
      @address_bus = AddressBus.new
      @cpu = CPU.new(@address_bus, debug:)
      @vic = @address_bus.vic
      @cia1 = @address_bus.cia1
      @cia2 = @address_bus.cia2
      @cycles = 0
      @nmi_asserted = false
      @init_handlers = []
      @pending_keys = nil
    end

    INIT_THRESHOLD = 2_500_000

    def cycle!
      handle_init if @cycles == INIT_THRESHOLD
      feed_keyboard if @pending_keys

      @vic.cycle!
      @cia1.cycle!
      @cia2.cycle!

      @cpu.irq = @cia1.interrupted? || @vic.interrupted?

      nmi = @cia2.interrupted?
      @cpu.nmi = true if nmi && !@nmi_asserted
      @nmi_asserted = nmi

      @cpu.cycle! if @cpu.pending_write? || !@vic.ba_low?

      @cycles += 1
    end

    def load_prg(data)
      uint16(data[0], data[1]).tap do |load_addr|
        ram.write(load_addr, data[2..])
      end
    end

    def attach_cartridge(cartridge)
      address_bus.attach_cartridge(cartridge)
      cpu.reset!
    end

    def mount(storage)
      load_trap = KernalTrap::Load.new(cpu:, bus: address_bus, storage:)
      cpu.install_trap(KernalTrap::Load::ADDRESS) { load_trap.call }
      return unless storage.respond_to?(:write_file)

      save_trap = KernalTrap::Save.new(cpu:, bus: address_bus, storage:)
      cpu.install_trap(KernalTrap::Save::ADDRESS) { save_trap.call }
    end

    def capture_output
      @capture_output ||= ChroutTrap.new(cpu:, bus: address_bus).tap do |trap|
        cpu.install_trap(ChroutTrap::ADDRESS) { trap.call }
      end
    end

    def inspect
      "#<#{self.class.name} cycles=#{@cycles} cpu=(#{@cpu.inspect})>"
    end

    def on_init(&block)
      if booting?
        @init_handlers << block
      else
        block.call
      end
    end

    private

    def booting?
      @cycles < init_threshold
    end

    def handle_init
      @init_handlers.each(&:call)
    end

    def init_threshold
      INIT_THRESHOLD
    end
  end
end
