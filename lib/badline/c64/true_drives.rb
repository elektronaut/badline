# frozen_string_literal: true

module Badline
  class Computer
    # The true drives on the machine's serial bus: a Drive1541, and a
    # Drive1581 (Drive1581::Slot), each in a field of its own. Computer,
    # Vic20 and C128 each include it.
    module TrueDrives
      include Drive1581::Slot

      # Plugs in a Drive1541, which then runs alongside the machine on its
      # own clock and talks to it over the serial bus. The serial traps stop
      # answering the drive's device number, so the KERNAL's TALK, LISTEN and
      # byte transfers reach the drive. The LOAD and SAVE traps stay, and
      # still serve a mounted image.
      def attach_drive1541(drive)
        @iec_bus.detach(@drive1541) if @drive1541
        drive.host_clock_hz = timing.clock_hz
        @drive1541 = drive
        drive.connect(@iec_bus)
        @serial_trap&.device = serial_trap_device
        drive1541_attached
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

      private

      # The device number the serial traps answer: device 8, unless a true
      # drive is on the bus as device 8.
      def serial_trap_device
        device = KernalTrap::Routine::DEVICE
        @drive1541&.device == device || drive1581_on_device8? ? nil : device
      end

      # What the machine does as a 1541 goes on its bus. The VIC-20 waits
      # for its DOS to boot before typing.
      def drive1541_attached = nil

      # A true 1541 on the serial bus, with its device number.
      def load_drive1541(input)
        return detach_drive1541 unless input.boolean?

        device = input.int
        detach_drive1541 if @drive1541 && @drive1541.device != device
        attach_drive1541(Drive1541.new(device:)) unless @drive1541
        @drive1541.load_state(input)
      end
    end
  end
end
