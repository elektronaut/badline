# frozen_string_literal: true

module Badline
  class Vic20
    # What plugs into the VIC-20 besides its chips: cartridge ROM in the
    # expansion blocks, the disk device 8 serves through the KERNAL traps,
    # and a true 1541 or 1581 on the serial bus.
    module Attachments
      include Drive1581::Slot

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

      # Puts the storage in device 8. Mounting again swaps the disk at any
      # point while the machine runs: the drive keeps its RAM and its
      # status.
      def mount(storage)
        return @drive.insert(storage) if @drive

        @drive = KernalTrap::Drive.new(storage)
        layout = KernalTrap::VIC20_LAYOUT
        load_trap = KernalTrap::Load.new(cpu:, bus:, layout:, drive: @drive)
        cpu.install_trap(layout.load) { load_trap.call }
        @serial_trap = KernalTrap::Serial.new(cpu:, bus:, layout:, drive: @drive, device: serial_trap_device).install
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
        @serial_trap.uninstall
        @serial_trap = nil
        @save_trap = nil
        @drive = nil
      end

      # Whether device 8 serves a disk or directory through the traps.
      def mounted? = !@drive.nil?

      # Plugs in a Drive1541, which then runs alongside the VIC-20 on its own
      # clock and talks to it over the serial bus. The serial traps stop
      # answering the drive's device number, so the KERNAL's TALK, LISTEN
      # and byte transfers reach the drive. The LOAD and SAVE traps stay,
      # and still serve a mounted image.
      #
      # A drive that powers on with the machine takes longer to boot than
      # the KERNAL, and doesn't answer the bus until it has, so the
      # machine's on_init handlers wait for it too.
      def attach_drive1541(drive)
        @init_threshold = [@init_threshold, DRIVE_BOOT_CYCLES].max if @cycles < @init_threshold
        @iec_bus.detach(@drive1541) if @drive1541
        drive.host_clock_hz = timing.clock_hz
        @drive1541 = drive
        drive.connect(@iec_bus)
        @serial_trap&.device = serial_trap_device
      end

      # The true drive on the serial bus: the Drive1581 ahead of the
      # Drive1541, or nil.
      def true_drive = @drive1581 || @drive1541

      # Plugs a Drive1541 in as device 8, in place of a 1581 there, and
      # returns it.
      def plug_true_drive
        detach_drive1581 if drive1581_on_device8?
        Drive1541.new.tap { |drive| attach_drive1541(drive) }
      end

      # Unplugs the Drive1541, leaving the serial bus with nothing on it.
      def detach_drive1541
        return unless @drive1541

        @iec_bus.detach(@drive1541)
        @drive1541 = nil
        @serial_trap&.device = serial_trap_device
      end

      # Records what the KERNAL prints through CHROUT (ChroutTrap).
      def capture_output
        @capture_output ||= ChroutTrap.new(cpu:, bus:, layout: KernalTrap::VIC20_LAYOUT).tap do |trap|
          cpu.install_trap(ChroutTrap::ADDRESS) { trap.call }
        end
      end

      private

      # The device number the serial traps answer: device 8, unless a true
      # drive is on the bus as device 8.
      def serial_trap_device
        device = KernalTrap::Routine::DEVICE
        @drive1541&.device == device || drive1581_on_device8? ? nil : device
      end

      # A 1581 plugged in, as a 1541 does, holds the machine's on_init
      # handlers back until its DOS has booted.
      def drive1581_attached
        @init_threshold = [@init_threshold, Drive1581::BOOT_CYCLES].max if @cycles < @init_threshold
      end
    end
  end
end
