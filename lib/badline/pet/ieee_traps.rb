# frozen_string_literal: true

module Badline
  class PET
    # The disk device 8 serves through the traps on the KERNAL's IEEE-488
    # primitives (KernalTrap::IEEE), and CHROUT capture. There is no LOAD
    # or SAVE trap: the ROM's own LOAD and SAVE, and BASIC 4's disk
    # commands, run through the primitives.
    module IEEETraps
      # Puts the storage in device 8. Mounting again swaps the disk while
      # the machine runs, and the drive keeps its RAM and its status.
      def mount(storage)
        return @dos.insert(storage) if @dos

        @dos = dos = KernalTrap::DOS.new(storage, channel_saves: true)
        @ieee_trap = KernalTrap::IEEE.new(cpu:, bus:, layout: trap_layout, dos:).install
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

      # Records what the KERNAL prints through CHROUT (KernalTrap::Chrout).
      def capture_output
        @capture_output ||= KernalTrap::Chrout.new(cpu:, bus:, layout: trap_layout).tap do |trap|
          cpu.install_trap(KernalTrap::Chrout::ADDRESS) { trap.call }
        end
      end

      private

      # The IEEELayout of the KERNAL the model runs.
      def trap_layout = @model.trap_layout
    end
  end
end
