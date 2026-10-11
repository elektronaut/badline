# frozen_string_literal: true

module Badline
  class C64
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
        @iec_bus = Drives::SerialBus.new
        @cia2.peripheral = @iec_bus
        @cia2.on_port_a_write { push_serial_lines }
        push_serial_lines
      end

      # Pushes the lines CIA 2's port A pulls into the serial bus.
      def push_serial_lines
        @iec_bus.host_lines = @cia2.port_a_lines
      end
    end
  end
end
