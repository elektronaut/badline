# frozen_string_literal: true

require "badline/drives/model2031"
require "badline/drives/model8050"

module Badline
  class PET
    # The PET's true drive: a Drives::Model2031 on the IEEE-488 bus
    # (IEEEPorts), clocked after the CPU each cycle and reset with it, as
    # the PET's RES line reaches IFC. The traps on the KERNAL's primitives
    # (IEEETraps) leave device 8 to the drive while it is device 8.
    module IEEEDrive
      # The 2031 on the bus, or nil.
      attr_reader :drive2031

      # The 8050 or 8250 on the bus, or nil.
      attr_reader :drive8050

      # Plugs in a Drives::Model2031, in place of the one there.
      def attach_drive2031(drive)
        detach_drive2031
        detach_drive8050
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

      # Plugs in a Drives::Model8050 or Model8250, in place of the drive
      # there.
      def attach_drive8050(drive)
        detach_drive2031
        detach_drive8050
        drive.host_clock_hz = 1_000_000
        drive.connect(@ieee.bus)
        @drive8050 = drive
        @ieee.lines_written
        @ieee_trap&.device = trap_device
        @init_threshold = [@init_threshold, Badline::Drives::Model8050::BOOT_CYCLES].max if @cycles < @init_threshold
      end

      # Unplugs the 8050, leaving it on a bus of its own.
      def detach_drive8050
        drive = @drive8050
        return unless drive

        drive.connect(Badline::Drives::IEEEBus.new)
        @drive8050 = nil
        @ieee_trap&.device = trap_device
      end

      # Plugs in an 8050, or an 8250 for +model+ "8250", as device 8, in
      # place of the drive there, and returns it.
      def plug_drive8050(model = "8050")
        drive = model == "8250" ? Badline::Drives::Model8250.new : Badline::Drives::Model8050.new
        drive.tap { |unit| attach_drive8050(unit) }
      end

      # The true drive on the bus, or nil.
      def true_drive = @drive8050 || @drive2031

      # Plugs in a 2031 as device 8, in place of the drive there, and
      # returns it.
      def plug_true_drive
        Badline::Drives::Model2031.new.tap { |drive| attach_drive2031(drive) }
      end

      private

      def init_ieee_drives
        @drive2031 = nil
        @drive8050 = nil
      end

      # The true drive's cycles for one of the PET's.
      def clock_ieee_drives
        @drive2031&.host_cycle!
        @drive8050&.host_cycle!
      end

      # The RES line reaches the true drive as IFC.
      def reset_ieee_drives
        @drive2031&.reset!
        @drive8050&.reset!
      end

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
