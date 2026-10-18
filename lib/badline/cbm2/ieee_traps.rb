# frozen_string_literal: true

module Badline
  class CBM2
    # The disk device 8 serves through the traps on the KERNAL's IEEE-488
    # primitives (KernalTrap::IEEE, IEEELayout), and CHROUT capture. There
    # is no LOAD or SAVE trap: the ROM's own LOAD and SAVE, which move the
    # bytes into the segment they name, and BASIC's disk commands run
    # through the primitives. Other devices find nobody on the bus, and
    # the KERNAL reports them not present.
    module IEEETraps
      # Puts the storage in device 8. Mounting again swaps the disk while
      # the machine runs, and the drive keeps its RAM and its status.
      def mount(storage)
        return @dos.insert(storage) if @dos

        @dos = dos = KernalTrap::DOS.new(storage, channel_saves: true)
        @ieee_trap = KernalTrap::IEEE.new(cpu:, bus:, layout: trap_layout, dos:).install
      end

      # Takes device 8's storage out, and the traps with it.
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

      # No true drive is on the bus.
      def true_drive = nil

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

      # The IEEELayout of the KERNAL the machine runs.
      def trap_layout = IEEELayout::LAYOUTS.fetch(@kernal)
    end
  end
end
