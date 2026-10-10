# frozen_string_literal: true

module Badline
  class Vic20
    # What plugs into the VIC-20 besides its chips: cartridge ROM in the
    # expansion blocks, the disk device 8 serves through the KERNAL traps
    # (Computer::KernalTraps), and a true 1541 or 1581 on the serial bus
    # (Computer::TrueDrives).
    module Attachments
      include Computer::TrueDrives
      include Computer::KernalTraps

      # The cycle by which a 1541 switched on with the machine has run its
      # DOS's reset, the RAM test and the ROM checksum, and waits on the
      # bus, with a margin: about 1.1 million of the VIC-20's cycles.
      DRIVE_BOOT_CYCLES = 1_300_000

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

      private

      # The VIC-20's KERNAL, which the traps stand in for.
      def trap_layout = KernalTrap::VIC20_LAYOUT

      def trap_bus = @bus

      # A drive that powers on with the machine takes longer to boot than
      # the KERNAL, and doesn't answer the bus until it has, so the
      # machine's on_init handlers wait for it too.
      def drive1541_attached
        @init_threshold = [@init_threshold, DRIVE_BOOT_CYCLES].max if @cycles < @init_threshold
      end

      # A 1581 plugged in, as a 1541 does, holds the machine's on_init
      # handlers back until its DOS has booted.
      def drive1581_attached
        @init_threshold = [@init_threshold, Drive1581::BOOT_CYCLES].max if @cycles < @init_threshold
      end
    end
  end
end
