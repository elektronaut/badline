# frozen_string_literal: true

module Badline
  class Computer
    # What plugs into the machine besides its chips, the cartridge, the
    # disk device 8 serves through the traps, a true 1541 and an REU, and
    # their state for a snapshot.
    module Attachments
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
      # drive reset clears, and its status.
      def mount(storage)
        return @drive.insert(storage) if @drive

        @drive = KernalTrap::Drive.new(storage)
        load_trap = KernalTrap::Load.new(cpu:, bus: address_bus, drive: @drive)
        cpu.install_trap(KernalTrap::Load::ADDRESS) { load_trap.call }
        @serial_trap = KernalTrap::Serial.new(cpu:, bus: address_bus, drive: @drive, device: serial_trap_device).install
        save_trap = @save_trap = KernalTrap::Save.new(cpu:, bus: address_bus, drive: @drive)
        cpu.install_trap(KernalTrap::Save::ADDRESS) { save_trap.call }
      end

      # Takes device 8's mounted storage out, and with it the LOAD, SAVE and
      # serial traps, so the KERNAL's routines go out over the serial bus.
      # Mounting again starts a new drive, with its RAM cleared.
      def unmount
        return unless @drive

        cpu.remove_trap(KernalTrap::Load::ADDRESS)
        cpu.remove_trap(KernalTrap::Save::ADDRESS)
        @serial_trap.device = nil
        @serial_trap = nil
        @save_trap = nil
        @drive = nil
      end

      # Whether device 8 serves a disk or directory through the traps.
      def mounted? = !@drive.nil?

      # Unplugs the Drive1541, leaving the serial bus with nothing on it.
      def detach_drive1541
        return unless @drive1541

        @iec_bus.detach(@drive1541)
        @drive1541 = nil
        @serial_trap&.device = serial_trap_device
      end

      private

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

      # A true 1541 on the serial bus. The leading flag is the bus itself,
      # which every machine now has, kept so older snapshots still load.
      def save_serial_bus(out)
        out.boolean(true).boolean(!@drive1541.nil?)
        return unless @drive1541

        out.int(@drive1541.device)
        @drive1541.save_state(out)
      end

      def load_serial_bus(input)
        input.boolean?
        return detach_drive1541 unless input.boolean?

        device = input.int
        detach_drive1541 if @drive1541 && @drive1541.device != device
        attach_drive1541(Drive1541.new(device:)) unless @drive1541
        @drive1541.load_state(input)
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
