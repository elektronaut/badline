# frozen_string_literal: true

module Badline
  class Vic20
    # What plugs into the VIC-20 besides its chips: cartridge ROM in the
    # expansion blocks, and the disk device 8 serves through the KERNAL
    # traps.
    module Attachments
      # Where BASIC's program starts, from TXTTAB, which the KERNAL sets at
      # boot by the RAM it finds: $1001 unexpanded, $0401 with the 3K
      # expansion and $1201 with 8K or more in BLK1.
      def basic_start = ram.peek16(0x2b)

      # Puts a cartridge's ROM chips, each a CRTFile::Chip with its address
      # and bytes, into their blocks, and switches the machine off and on,
      # as a cartridge goes in with the power off. The KERNAL then starts
      # the cartridge in BLK5 that signs itself with A0CBM.
      def attach_cartridge(chips)
        chips.each { |chip| @bus.map_rom(chip.address, chip.data) }
        power_cycle!
      end

      # Puts the storage in device 8. Mounting again swaps the disk at any
      # point while the machine runs: the drive keeps its RAM and its
      # status.
      def mount(storage)
        return @drive.insert(storage) if @drive

        @drive = KernalTrap::Drive.new(storage)
        layout = KernalTrap::VIC20_LAYOUT
        load_trap = KernalTrap::Load.new(cpu:, bus:, layout:, drive: @drive)
        cpu.install_trap(layout.load) { load_trap.call }
        @serial_trap = KernalTrap::Serial.new(cpu:, bus:, layout:, drive: @drive).install
        save_trap = @save_trap = KernalTrap::Save.new(cpu:, bus:, layout:, drive: @drive)
        cpu.install_trap(layout.save) { save_trap.call }
      end

      # Takes device 8's mounted storage out, and with it the LOAD, SAVE and
      # serial traps, so the KERNAL's routines go out over the serial bus.
      # Mounting again starts a new drive, with its RAM cleared.
      def unmount
        return unless @drive

        cpu.remove_trap(KernalTrap::VIC20_LAYOUT.load)
        cpu.remove_trap(KernalTrap::VIC20_LAYOUT.save)
        @serial_trap.device = nil
        @serial_trap = nil
        @save_trap = nil
        @drive = nil
      end

      # Whether device 8 serves a disk or directory through the traps.
      def mounted? = !@drive.nil?

      # Records what the KERNAL prints through CHROUT (ChroutTrap).
      def capture_output
        @capture_output ||= ChroutTrap.new(cpu:, bus:, layout: KernalTrap::VIC20_LAYOUT).tap do |trap|
          cpu.install_trap(ChroutTrap::ADDRESS) { trap.call }
        end
      end
    end
  end
end
