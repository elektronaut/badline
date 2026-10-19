# frozen_string_literal: true

require "badline/drives/ieee_models"
require "badline/drives/model2031"
require "badline/drives/model8050"
require "badline/drives/model9060"
require "badline/drives/model1001"
require "badline/drives/model4040"

module Badline
  module Machine
    # A machine's true drive on its IEEE-488 bus, one at a time, of a model
    # Drives::IEEEModels names: a Drives::Model2031, Model8050, Model8250,
    # Model1001, Model4040, Model3040, Model9060 or Model9090. It is clocked
    # after the CPU each cycle at the machine's clock (ieee_host_clock_hz)
    # and reset with it, as the machine's RES line reaches IFC. The traps on
    # the KERNAL's primitives leave device 8 to the drive while it is device
    # 8 (trap_device). The PET (PET::IEEEDrive) and the CBM-II
    # (CBM2::IEEEDrive) include it.
    #
    # The machine's @ieee is its side of the bus: #bus, the
    # Drives::IEEEBus, #push_lines, which shows the drives the lines the
    # machine pulls now, and #cycle_lines, which does so once a cycle if
    # the machine doesn't push them as its chips are written.
    module IEEEDrives
      # The true drive on the bus, or nil.
      attr_reader :true_drive

      # The model plug_true_drive plugs in, one Drives::IEEEModels names.
      attr_reader :true_drive_model

      # Plugs in the drive, in place of the drive there.
      def attach_ieee_drive(drive)
        detach_ieee_drive
        drive.host_clock_hz = ieee_host_clock_hz
        drive.connect(@ieee.bus)
        @ieee.push_lines
        @true_drive = drive
        @ieee_trap&.device = trap_device
        @init_threshold = [@init_threshold, drive.boot_cycles].max if @cycles < @init_threshold
      end

      # Unplugs the true drive, leaving it on a bus of its own.
      def detach_ieee_drive
        drive = @true_drive
        return unless drive

        drive.connect(Badline::Drives::IEEEBus.new)
        @true_drive = nil
        @ieee_trap&.device = trap_device
      end

      # Plugs in the model as +device+, in place of the drive there, and
      # returns it.
      def plug_ieee_drive(model, device: 8)
        build_ieee_drive(model, device).tap { |drive| attach_ieee_drive(drive) }
      end

      # The drive of a dual unit a disk image given on its own goes in
      # (Media::TrueDrive): drive 0.
      def disk_drive_number = 0

      # Plugs in the model true_drive_model names as device 8, in place of
      # the drive there, and returns it.
      def plug_true_drive = plug_ieee_drive(@true_drive_model)

      # Settles for a snapshot, then runs on until the true drive is where
      # VICE saves it (the drive's settled_for_vice?) between instructions
      # with the machine's, or for so many cycles, then on to the machine's
      # next instruction. It stands in for Machine::Settling's, which the
      # machines include first.
      def settle_for_vice!
        ran = settle_for_snapshot!
        drive = @true_drive
        return ran if drive.nil?

        until ran >= Machine::Settling::LIMIT || (drive.settled_for_vice? && settled_for_snapshot?)
          cycle!
          ran += 1
        end
        ran + settle_for_snapshot!
      end

      private

      def init_ieee_drives(true_drive_model)
        unless Badline::Drives::IEEEModels::NAMES.include?(true_drive_model)
          raise ArgumentError, "no true drive model #{true_drive_model} for the IEEE-488 bus"
        end

        @true_drive_model = true_drive_model
        @true_drive = nil
      end

      # A new drive of the model as +device+.
      def build_ieee_drive(model, device)
        case model
        when "8050" then Badline::Drives::Model8050.new(device:)
        when "8250" then Badline::Drives::Model8250.new(device:)
        when "1001" then Badline::Drives::Model1001.new(device:)
        when "4040" then Badline::Drives::Model4040.new(device:)
        when "3040" then Badline::Drives::Model3040.new(device:)
        when "9060" then Badline::Drives::Model9060.new(device:)
        when "9090" then Badline::Drives::Model9090.new(device:)
        else Badline::Drives::Model2031.new(device:)
        end
      end

      # The true drive's cycles for one of the machine's, after the lines
      # it pulls.
      def clock_ieee_drives
        drive = @true_drive
        return unless drive

        @ieee.cycle_lines
        drive.host_cycle!
      end

      # The RES line reaches the true drive as IFC.
      def reset_ieee_drives
        @true_drive&.reset!
      end

      def save_ieee_drive_fields(out)
        out.text("host.ieee_drive_model", @true_drive_model)
      end

      def load_ieee_drive_fields(input)
        @true_drive_model = input.choice("host.ieee_drive_model", Badline::Drives::IEEEModels::NAMES,
                                         @true_drive_model)
      end

      # The true drive as keyed snapshot modules named from its device
      # number: BL-D8, BL-D8-CPU and so on for device 8.
      def save_drive_modules(sections)
        drive = @true_drive
        drive&.save_modules(sections, "BL-D#{drive.device}")
        sections
      end

      # The true drive a snapshot's modules hold, of the model they name,
      # built afresh unless the same model is on the bus as the same
      # device, or none when they hold no drive. The bus then carries the
      # machine's lines as its chips left them.
      def load_drive_modules(modules)
        device = 8
        input = modules.optional("BL-D8")
        while input.nil? && device < 15
          device += 1
          input = modules.optional("BL-D#{device}")
        end
        if input
          load_ieee_drive_modules(modules, input, device)
        else
          detach_ieee_drive
        end
        @ieee.push_lines
      end

      def load_ieee_drive_modules(modules, input, device)
        model = input.text("model", Badline::Drives::IEEEModels::DEFAULT)
        model = Badline::Drives::IEEEModels::DEFAULT unless Badline::Drives::IEEEModels::NAMES.include?(model)
        drive = @true_drive
        detach_ieee_drive if drive && (drive.device != device || drive.model_name != model)
        drive = @true_drive || plug_ieee_drive(model, device:)
        drive.load_modules(modules, input, "BL-D#{device}")
      end
    end
  end
end
