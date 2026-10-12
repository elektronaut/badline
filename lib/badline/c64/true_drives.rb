# frozen_string_literal: true

module Badline
  class C64
    # The true drives on the machine's serial bus: a Drives::Model1541, and a
    # Drives::Model1581 (Drives::Model1581::Slot), each in a field of its own. C64,
    # Vic20 and C128 each include it.
    module TrueDrives
      include Drives::Model1581::Slot

      # The true drive models a snapshot names.
      DRIVE_MODELS = %w[1541 1551 1571 1581].freeze

      # Plugs in a Drives::Model1541, which then runs alongside the machine on its
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

      # The true drive on the serial bus: the Drives::Model1581 ahead of the
      # Drives::Model1541, or nil.
      def true_drive = @drive1581 || @drive1541

      # Plugs a Drives::Model1541 in as device 8, in place of a 1581 there, and
      # returns it.
      def plug_true_drive
        detach_drive1581 if drive1581_on_device8?
        Drives::Model1541.new.tap { |drive| attach_drive1541(drive) }
      end

      # The true drives as keyed snapshot modules, each named from its device
      # number: BL-D8, BL-D8-CPU and so on for device 8.
      def save_drive_modules(sections)
        drive1541 = @drive1541
        drive1541&.save_modules(sections, "BL-D#{drive1541.device}")
        drive1581 = @drive1581
        drive1581&.save_modules(sections, "BL-D#{drive1581.device}")
        save_drive1571_modules(sections)
        save_drive1551_modules(sections)
        sections
      end

      # The true drives a snapshot's modules hold, built afresh unless the
      # same model is on the bus as the same device. A drive the snapshot
      # doesn't have comes off the bus.
      def load_drive_modules(modules)
        models = []
        8.upto(11) do |device|
          input = modules.optional("BL-D#{device}")
          next unless input

          model = input.choice("model", DRIVE_MODELS, "1541")
          load_drive_model(modules, input, device, model)
          models << model
        end
        detach_drive1541 unless models.include?("1541")
        detach_drive1581 unless models.include?("1581")
        detach_drive1571 unless models.include?("1571")
        detach_drive1551 unless models.include?("1551")
      end

      # Unplugs the Drives::Model1541, leaving the serial bus with nothing on it.
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

      def load_drive_model(modules, input, device, model)
        case model
        when "1581" then load_drive1581_modules(modules, input, device)
        when "1571" then load_drive1571_modules(modules, input, device)
        when "1551" then load_drive1551_modules(modules, input, device)
        else load_drive1541_modules(modules, input, device)
        end
      end

      def load_drive1541_modules(modules, input, device)
        detach_drive1541 if @drive1541 && @drive1541.device != device
        attach_drive1541(Drives::Model1541.new(device:)) unless @drive1541
        @drive1541.load_modules(modules, input, "BL-D#{device}")
      end

      def load_drive1581_modules(modules, input, device)
        detach_drive1581 if @drive1581 && @drive1581.device != device
        attach_drive1581(Drives::Model1581.new(device:)) unless @drive1581
        @drive1581.load_modules(modules, input, "BL-D#{device}")
      end

      # The C128D's 1571, which only the C128 has (C128::Drives).
      def save_drive1571_modules(sections) = sections

      def load_drive1571_modules(_modules, input, _device)
        input.adjust("a 1571 doesn't plug into this machine, left out")
      end

      def detach_drive1571 = nil

      # The 264 series' 1551, which only the Plus/4 has (Plus4::TCBMDrive).
      def save_drive1551_modules(sections) = sections

      def load_drive1551_modules(_modules, input, _device)
        input.adjust("a 1551 doesn't plug into this machine, left out")
      end

      def detach_drive1551 = nil
    end
  end
end
