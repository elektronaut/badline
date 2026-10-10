# frozen_string_literal: true

module Badline
  class Computer
    # What plugs into the machine besides its chips, the cartridge, its
    # true drives (TrueDrives) and an REU, and their state for a snapshot.
    # The disk device 8 serves through the traps is KernalTraps'.
    module Attachments
      include TrueDrives

      # Puts the cartridge in the expansion port and wires its clock and NMI
      # line to the machine, leaving the machine's state as it is. A
      # restored snapshot's cartridge comes back through here.
      def connect_cartridge(cartridge)
        cartridge.clock = -> { @cycles }
        cartridge.on_nmi_change { |level| @cartridge_nmi = level }
        address_bus.attach_cartridge(cartridge)
      end

      # The serial bus, which CIA 2's port A drives through the C64's own
      # inverters and reads back on PA6 and PA7, with or without a drive on
      # it.
      attr_reader :iec_bus

      private

      # CIA 2's port A drives the serial bus, which reads CLK and DATA back
      # into it.
      def plug_serial_bus
        @iec_bus = IECBus.new
        @cia2.peripheral = @iec_bus
        @cia2.on_port_a_write { push_serial_lines }
        push_serial_lines
      end

      # Pushes the lines CIA 2's port A pulls into the serial bus.
      def push_serial_lines
        @iec_bus.host_lines = @cia2.port_a_lines
      end

      def save_cartridge(out)
        cartridge = address_bus.cartridge
        out.boolean(!cartridge.nil?)
        cartridge&.save_setup(out)
      end

      # A cartridge comes back built afresh from the setup it was built
      # with, before the address bus puts its state into it.
      def load_cartridge(input)
        if input.boolean?
          connect_cartridge(Cartridge.from_setup(input))
        elsif address_bus.cartridge
          address_bus.detach_cartridge
        end
      end

      # A true 1541 on the serial bus, then a 1581. The leading flag is the
      # bus itself, which every machine now has.
      def save_serial_bus(out)
        out.boolean(true).boolean(!@drive1541.nil?)
        if @drive1541
          out.int(@drive1541.device)
          @drive1541.save_state(out)
        end
        save_drive1581(out)
      end

      def load_serial_bus(input)
        input.boolean?
        load_drive1541(input)
        load_drive1581(input)
      end

      # The REU, which the setup says the machine has, and whether it has
      # asked for the bus. Its IRQ line reaches the CPU as it was.
      def save_reu(out)
        @reu&.save_state(out)
        out.boolean(@dma)
      end

      def load_reu(input)
        @reu&.load_state(input)
        @reu_irq = @reu ? @reu.irq? : false
        @dma = input.boolean?
      end
    end
  end
end
