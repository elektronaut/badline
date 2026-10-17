# frozen_string_literal: true

require "badline/drives/model2031"

module Badline
  class PET
    # The PET's true drive: a Drives::Model2031 on the IEEE-488 bus
    # (IEEEPorts), clocked after the CPU each cycle and reset with it, as
    # the PET's RES line reaches IFC. The traps on the KERNAL's primitives
    # (IEEETraps) leave device 8 to the drive while it is device 8.
    module IEEEDrive
      # The 2031 on the bus, or nil.
      attr_reader :drive2031

      # Plugs in a Drives::Model2031, in place of the one there.
      def attach_drive2031(drive)
        detach_drive2031
        drive.host_clock_hz = 1_000_000
        drive.connect(@ieee.bus)
        @drive2031 = drive
        @ieee.lines_written
        @ieee_trap&.device = trap_device
        @init_threshold = [@init_threshold, Badline::Drives::Model2031::BOOT_CYCLES].max if @cycles < @init_threshold
      end

      # Unplugs the 2031, leaving it on a bus of its own.
      def detach_drive2031
        drive = @drive2031
        return unless drive

        drive.connect(Badline::Drives::IEEEBus.new)
        @drive2031 = nil
        @ieee_trap&.device = trap_device
      end

      # The true drive on the bus, or nil.
      def true_drive = @drive2031

      # Plugs in a 2031 as device 8, in place of the drive there, and
      # returns it.
      def plug_true_drive
        Badline::Drives::Model2031.new.tap { |drive| attach_drive2031(drive) }
      end

      private

      # The 2031 as keyed snapshot modules named from its device number:
      # BL-D8, BL-D8-CPU and so on for device 8.
      def save_drive_modules(sections)
        drive = @drive2031
        drive&.save_modules(sections, "BL-D#{drive.device}")
        sections
      end

      # The 2031 a snapshot's modules hold, built afresh unless one is on
      # the bus as the same device, or none when they hold no drive. The
      # bus then carries the PET's lines as its chips left them.
      def load_drive_modules(modules)
        device = 8
        input = modules.optional("BL-D8")
        while input.nil? && device < 11
          device += 1
          input = modules.optional("BL-D#{device}")
        end
        if input
          detach_drive2031 if @drive2031 && @drive2031.device != device
          attach_drive2031(Badline::Drives::Model2031.new(device:)) unless @drive2031
          @drive2031.load_modules(modules, input, "BL-D#{device}")
        else
          detach_drive2031
        end
        @ieee.lines_written
      end
    end
  end
end
