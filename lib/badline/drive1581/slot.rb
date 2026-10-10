# frozen_string_literal: true

module Badline
  class Drive1581
    # A machine's place for a Drive1581 on its serial bus, in a field of
    # its own beside its other true drives, so none of them makes another's
    # per-cycle call a union. The C64, the VIC-20 and the C128 include it,
    # and run the drive from their cycle as they run a 1541.
    #
    # A 1581 reads only .d81 images and the others none, so a .d81 put in
    # device 8 swaps the true drive there for a 1581, and any other disk
    # swaps a 1581 back for the machine's own true drive
    # (Media::TrueDrive).
    module Slot
      attr_reader :drive1581

      # Plugs in a Drive1581, which then runs alongside the machine on its
      # own clock and talks to it over the serial bus, as a 1541 does.
      def attach_drive1581(drive)
        @iec_bus.detach(@drive1581) if @drive1581
        drive.host_clock_hz = timing.clock_hz
        @drive1581 = drive
        drive.connect(@iec_bus)
        @serial_trap&.device = serial_trap_device
        drive1581_attached
      end

      # Unplugs the Drive1581.
      def detach_drive1581
        return unless @drive1581

        @iec_bus.detach(@drive1581)
        @drive1581 = nil
        @serial_trap&.device = serial_trap_device
      end

      # Plugs in a 1581 as device 8, in place of the true drive there, and
      # returns it.
      def plug_drive1581
        unplug_device8
        Drive1581.new.tap { |drive| attach_drive1581(drive) }
      end

      private

      # Unplugs the 1541 if it is device 8, for a 1581 to take its place.
      def unplug_device8
        detach_drive1541 if @drive1541&.device == KernalTrap::Routine::DEVICE
      end

      # What the machine does as a 1581 goes on its bus. The VIC-20 waits
      # for its DOS to boot before typing.
      def drive1581_attached = nil

      # Whether the 1581 is device 8.
      def drive1581_on_device8? = @drive1581&.device == KernalTrap::Routine::DEVICE

      # The 1581 on the serial bus, with its device number.
      def save_drive1581(out)
        out.boolean(!@drive1581.nil?)
        return unless @drive1581

        out.int(@drive1581.device)
        @drive1581.save_state(out)
      end

      def load_drive1581(input)
        return detach_drive1581 unless input.boolean?

        device = input.int
        detach_drive1581 if @drive1581 && @drive1581.device != device
        attach_drive1581(Drive1581.new(device:)) unless @drive1581
        @drive1581.load_state(input)
      end
    end
  end
end
