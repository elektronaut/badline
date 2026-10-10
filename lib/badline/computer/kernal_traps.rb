# frozen_string_literal: true

module Badline
  class Computer
    # The disk device 8 serves through the LOAD, SAVE and serial traps, and
    # CHROUT capture, on the KERNAL the machine runs. Computer, Vic20 and
    # C128 each include it and answer two private methods: #trap_layout,
    # the KernalTrap::Layout of that KERNAL, and #trap_bus, the bus the
    # traps read and write through.
    module KernalTraps
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

      # The path of the disk or directory device 8 serves through the
      # traps, or an empty one.
      def mounted_path = @drive.nil? ? "" : @drive.path

      # Records what the KERNAL prints through CHROUT (ChroutTrap).
      def capture_output
        @capture_output ||= ChroutTrap.new(cpu:, bus: trap_bus, layout: trap_layout).tap do |trap|
          cpu.install_trap(ChroutTrap::ADDRESS) { trap.call }
        end
      end

      private

      def install_kernal_traps(layout)
        @trap_layout = layout
        load_trap = KernalTrap::Load.new(cpu:, bus: trap_bus, layout:, drive: @drive)
        cpu.install_trap(layout.load) { load_trap.call }
        @serial_trap = KernalTrap::Serial.new(cpu:, bus: trap_bus, layout:, drive: @drive,
                                              device: serial_trap_device).install
        save_trap = @save_trap = KernalTrap::Save.new(cpu:, bus: trap_bus, layout:, drive: @drive)
        cpu.install_trap(layout.save) { save_trap.call }
      end

      def remove_kernal_traps
        cpu.remove_trap(@trap_layout.load)
        cpu.remove_trap(@trap_layout.save)
        @serial_trap.uninstall
        @serial_trap = nil
        @save_trap = nil
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
    end
  end
end
