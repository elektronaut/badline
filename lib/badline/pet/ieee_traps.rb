# frozen_string_literal: true

module Badline
  class PET
    # The disk device 8 serves through the traps on the KERNAL's IEEE-488
    # primitives (KernalTrap::IEEE), and CHROUT capture. There is no LOAD
    # or SAVE trap: the ROM's own LOAD and SAVE, and BASIC 4's disk
    # commands, run through the primitives.
    module IEEETraps
      # Puts the storage in device 8. Mounting again swaps the disk while
      # the machine runs, and the drive keeps its RAM and its status. The
      # traps leave device 8 to a true drive with that number.
      def mount(storage)
        return @dos.insert(storage) if @dos

        @dos = dos = KernalTrap::DOS.new(storage, channel_saves: true)
        @ieee_trap = KernalTrap::IEEE.new(cpu:, bus:, layout: trap_layout, dos:).install
        @ieee_trap.device = trap_device
        @ieee_trap
      end

      # Takes device 8's storage out, and the traps with it, so the KERNAL
      # finds no device 8 on the bus.
      def unmount
        trap = @ieee_trap
        return unless trap

        trap.uninstall
        @ieee_trap = nil
        @dos = nil
      end

      # Whether device 8 serves a disk or directory through the traps.
      def mounted? = !@dos.nil?

      # The path of the disk or directory device 8 serves, or an empty one.
      def mounted_path = @dos.nil? ? "" : @dos.path

      # Device 8 through the traps in a keyed snapshot module (BL-TRAPDOS):
      # the storage under storage.*, the DOS, and the IEEE-488 trap under
      # ieee.*. Nothing mounted writes nothing.
      def save_trap_dos_fields(out)
        dos = @dos
        return unless dos

        Snapshot::StorageSetup.write_fields(dos.storage, out)
        dos.save_fields(out)
        @ieee_trap&.save_fields(out, "ieee.")
      end

      # `detached` mounts a disk image write-protected and no directory.
      def load_trap_dos_fields(input, detached: false)
        unmount
        return if input.missing?

        mount(Snapshot::StorageSetup.read_fields(input, detached:))
        @dos&.load_fields(input)
        @ieee_trap&.load_fields(input, "ieee.")
      end

      # Records what the KERNAL prints through CHROUT (KernalTrap::Chrout).
      def capture_output
        @capture_output ||= KernalTrap::Chrout.new(cpu:, bus:, layout: trap_layout).tap do |trap|
          cpu.install_trap(KernalTrap::Chrout::ADDRESS) { trap.call }
        end
      end

      private

      # The IEEELayout of the KERNAL the model runs.
      def trap_layout = @model.trap_layout

      # Device 8, unless a true drive is device 8.
      def trap_device
        device = KernalTrap::Routine::DEVICE
        true_drive&.device == device ? nil : device
      end
    end
  end
end
