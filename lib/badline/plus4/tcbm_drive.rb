# frozen_string_literal: true

module Badline
  class Plus4
    # The 264 series' true drives: a Drives::Model1541 and a
    # Drives::Model1581 on the serial bus (C64::TrueDrives), and a
    # Drives::Model1551 on TCBM, its interface's TIA in the expansion port
    # at $FEE0 for device 8 or $FEC0 for device 9. Each sits in a field of
    # its own, so none makes another's per-cycle call a union.
    #
    # A device number has one drive at a time: a 1551 takes the place of a
    # serial drive with its number, and the other way round.
    module TCBMDrive
      # The true drive models plug_true_drive builds.
      TRUE_DRIVE_MODELS = %w[1541 1551].freeze

      # The 1551 on TCBM, or nil.
      attr_reader :drive1551

      # The drive plug_true_drive plugs in, "1541" or "1551".
      attr_reader :true_drive_model

      # Plugs in a Drives::Model1551, its interface's TIA where its device
      # number puts it, in place of the TCBM interface's own there, and in
      # place of a serial drive with its number. The traps stop answering
      # device 8 when the drive is device 8.
      def attach_drive1551(drive)
        detach_drive1551
        device = drive.device
        detach_drive1541 if @drive1541&.device == device
        detach_drive1581 if @drive1581&.device == device
        drive.host_clock_hz = timing.clock_hz
        @drive1551 = drive
        @bus.plug_tia(drive.device, drive.host_tia)
        drive.on_renumber { |old| drive1551_renumbered(old) }
        @serial_trap&.device = serial_trap_device
        @init_threshold = [@init_threshold, Badline::Drives::Model1551::BOOT_CYCLES].max if @cycles < @init_threshold
      end

      # Unplugs the Drives::Model1551, leaving the TCBM interface's own TIA,
      # if there is one, in its place.
      def detach_drive1551
        drive = @drive1551
        return unless drive

        @bus.plug_tia(drive.device, tcbm_tia(drive.device))
        drive.on_renumber
        @drive1551 = nil
        @serial_trap&.device = serial_trap_device
      end

      # The true drive: a 1581 ahead of a 1551 ahead of a 1541.
      def true_drive = @drive1581 || @drive1551 || @drive1541

      # Plugs in the model true_drive_model names as device 8, in place of
      # the drive there, and returns it.
      def plug_true_drive
        return plug_drive1551 if @true_drive_model == "1551"

        unplug_device8
        detach_drive1581 if drive1581_on_device8?
        Badline::Drives::Model1541.new.tap { |drive| attach_drive1541(drive) }
      end

      # Plugs in a 1551 as device 8, in place of the drive there, and
      # returns it.
      def plug_drive1551
        Badline::Drives::Model1551.new.tap { |drive| attach_drive1551(drive) }
      end

      private

      def init_drives(true_drive_model)
        unless TRUE_DRIVE_MODELS.include?(true_drive_model)
          raise ArgumentError, "no true drive model #{true_drive_model} for the Plus/4"
        end

        @true_drive_model = true_drive_model
        @drive1541 = nil
        @drive1551 = nil
        @drive1581 = nil
      end

      def save_drive1551_modules(sections)
        drive = @drive1551
        drive&.save_modules(sections, "BL-D#{drive.device}")
        sections
      end

      def load_drive1551_modules(modules, input, device)
        return input.adjust("a 1551 as device #{device}, left out") unless [8, 9].include?(device)

        detach_drive1551 if @drive1551 && @drive1551.device != device
        attach_drive1551(Badline::Drives::Model1551.new(device:)) unless @drive1551
        @drive1551.load_modules(modules, input, "BL-D#{device}")
      end

      # The 1551's DEV line moved it from device +old+ to the other: its
      # interface's TIA moves with it, and the TCBM interface's own takes
      # its old place.
      def drive1551_renumbered(old)
        drive = @drive1551
        return unless drive

        @bus.plug_tia(old, tcbm_tia(old))
        @bus.plug_tia(drive.device, drive.host_tia)
        @serial_trap&.device = serial_trap_device
      end

      # The TCBM interface's own TIA for +device+, or nil without one.
      def tcbm_tia(device)
        tias = @tias
        return nil if tias.empty?

        device == 9 ? tias[1] : tias[0]
      end

      # Device 8, unless a true drive is device 8.
      def serial_trap_device
        device = KernalTrap::Routine::DEVICE
        on_device8 = @drive1551&.device == device || @drive1541&.device == device || drive1581_on_device8?
        on_device8 ? nil : device
      end

      # Unplugs the 1541 and the 1551 if either is device 8, for a 1581 to
      # take its place.
      def unplug_device8
        device = KernalTrap::Routine::DEVICE
        detach_drive1541 if @drive1541&.device == device
        detach_drive1551 if @drive1551&.device == device
      end
    end
  end
end
