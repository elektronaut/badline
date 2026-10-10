# frozen_string_literal: true

module Badline
  class Computer
    # What plugs into the machine besides its chips, the cartridge, the
    # disk device 8 serves through the traps, its true drives (TrueDrives)
    # and an REU, and their state for a snapshot.
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

      # Puts the storage in device 8. Mounting again swaps the disk at any
      # point while the machine runs: the drive keeps its RAM, which only a
      # drive reset clears, and its status. The traps go on the KERNAL the
      # machine runs (#trap_layout).
      def mount(storage)
        return @drive.insert(storage) if @drive

        @drive = KernalTrap::Drive.new(storage)
        install_kernal_traps(trap_layout)
      end

      # Takes device 8's mounted storage out, and with it the LOAD, SAVE and
      # serial traps, so the KERNAL's routines go out over the serial bus.
      # Mounting again starts a new drive, with its RAM cleared.
      def unmount
        return unless @drive

        remove_kernal_traps
        @drive = nil
      end

      # Whether device 8 serves a disk or directory through the traps.
      def mounted? = !@drive.nil?

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

      # The disk device 8 serves through the traps, with the traps' own
      # state: open channels, the drive's status and RAM, a SAVE under way.
      def save_trap_drive(out)
        out.boolean(!@drive.nil?)
        return unless @drive

        @drive.save_state(out)
        @serial_trap.save_state(out)
        @save_trap.save_state(out)
      end

      def load_trap_drive(input)
        return unmount unless input.boolean?

        storage = Storage.reopen(input)
        unmount
        mount(storage)
        @drive.load_state(input)
        @serial_trap.load_state(input)
        @save_trap.load_state(input)
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
