# frozen_string_literal: true

module Badline
  class C128
    # The true drives on the C128's serial bus: a Drive1541, the C128D's
    # built-in 1571 (Drive1571) or a 1581 (Drive1581::Slot), each in a
    # field of its own, so none makes another's per-cycle call a union.
    module Drives
      attr_reader :drive1571

      # Plugs in a Drive1571, which then runs alongside the C128 on its own
      # clock and talks to it over the serial bus, as attach_drive1541 does
      # for a 1541.
      def attach_drive1571(drive)
        @iec_bus.detach(@drive1571) if @drive1571
        drive.host_clock_hz = region.clock_hz
        @drive1571 = drive
        drive.connect(iec_bus)
        @serial_trap&.device = serial_trap_device
      end

      # Unplugs the Drive1571.
      def detach_drive1571
        return unless @drive1571

        @iec_bus.detach(@drive1571)
        @drive1571 = nil
        @serial_trap&.device = serial_trap_device
      end

      # The true drive on the bus, a 1581 ahead of the 1571 ahead of a 1541.
      def true_drive = @drive1581 || @drive1571 || @drive1541

      # Plugs in the C128D's 1571 as device 8, in place of a 1581 there, and
      # returns it.
      def plug_true_drive
        detach_drive1581 if drive1581_on_device8?
        Drive1571.new.tap { |drive| attach_drive1571(drive) }
      end

      private

      # The serial bus, with no disk in device 8's traps and no true drive.
      def init_drives
        @dos = nil
        @serial_trap = nil
        @save_trap = nil
        @drive1541 = nil
        @drive1571 = nil
        @drive1581 = nil
        plug_serial_bus
        plug_fast_serial
      end

      # Device 8, unless a true drive is on the bus as device 8.
      def serial_trap_device
        device = KernalTrap::Routine::DEVICE
        @drive1571&.device == device || @drive1541&.device == device || drive1581_on_device8? ? nil : device
      end

      # A 1581 plugged in holds the machine's on_init handlers back until
      # its DOS has booted, which takes longer than the C128 KERNAL's.
      def drive1581_attached
        @init_threshold = [@init_threshold, Drive1581::BOOT_CYCLES].max if @cycles < @init_threshold
      end

      # Unplugs the 1541 and the 1571 if either is device 8, for a 1581 to
      # take its place.
      def unplug_device8
        device = KernalTrap::Routine::DEVICE
        detach_drive1541 if @drive1541&.device == device
        detach_drive1571 if @drive1571&.device == device
      end

      # A true 1541 (Computer::Attachments#save_serial_bus), then a 1571 and
      # a 1581.
      def save_serial_bus(out)
        out.boolean(true).boolean(!@drive1541.nil?)
        if @drive1541
          out.int(@drive1541.device)
          @drive1541.save_state(out)
        end
        out.boolean(!@drive1571.nil?)
        if @drive1571
          out.int(@drive1571.device)
          @drive1571.save_state(out)
        end
        save_drive1581(out)
      end

      def load_serial_bus(input)
        input.boolean?
        load_drive1541(input)
        load_drive1571(input)
        load_drive1581(input)
      end

      def load_drive1571(input)
        return detach_drive1571 unless input.boolean?

        device = input.int
        detach_drive1571 if @drive1571 && @drive1571.device != device
        attach_drive1571(Drive1571.new(device:)) unless @drive1571
        @drive1571.load_state(input)
      end
    end
  end
end
