# frozen_string_literal: true

module Badline
  module Frontend
    # What the pause menu puts in the machine and takes out: disks, tapes
    # and cartridges, whether disks are writable, which carries over from
    # one disk to the next, and the disk's set, which PREVIOUS and NEXT step
    # through. It keeps what last went wrong for the page to show.
    class MenuMedia
      attr_reader :disk_path, :problem
      attr_writer :computer

      def initialize(disk_path, writable)
        @disk_path = disk_path
        @writable = writable
        @set_path = ""
        @set = []
        @problem = ""
        @computer = nil
      end

      def writable? = @writable

      def inserted?
        drive = @computer.drive1541
        drive.nil? ? @computer.mounted? : !drive.disk.nil?
      end

      # Puts a disk in device 8 or a tape in the datasette, `kind` :disk or
      # :tape.
      def insert(kind, path)
        @problem = ""
        if kind == :disk
          Media.insert_disk(@computer, path, read_only: !@writable)
          @disk_path = path
        else
          @computer.datasette.insert(Storage::TAP.new(path))
        end
      rescue ArgumentError, SystemCallError, Storage::TAP::FormatError, Storage::T64::FormatError,
             Storage::G64Image::FormatError => e
        @problem = e.message
      end

      # Does what the Drive page's :eject_disk, :previous_disk, :next_disk,
      # :protect or :unprotect asks.
      def drive(action)
        case action
        when :eject_disk then eject_disk
        when :previous_disk then step_disk(-1)
        when :next_disk then step_disk(1)
        else writable(action == :unprotect)
        end
      end

      def eject_disk
        drive = @computer.drive1541
        drive.nil? ? @computer.unmount : drive.insert(nil)
        @disk_path = ""
      end

      # Sets whether disks are writable, for the disk in the drive too,
      # which goes in again as the notch now says.
      def writable(writable)
        @writable = writable
        insert(:disk, @disk_path) if inserted? && !@disk_path.empty?
      end

      # The disks of the set the disk in the drive belongs to.
      def disk_set
        return [] if @disk_path.empty?

        unless @set_path == @disk_path
          @set = Media::DiskSet.around(@disk_path)
          @set_path = @disk_path
        end
        @set
      end

      # Puts the disk `step` before or after this one in its set in the
      # drive, if there is one.
      def step_disk(step)
        set = disk_set
        index = set.index(@disk_path)
        return if index.nil? || !(index + step).between?(0, set.size - 1)

        insert(:disk, set[index + step])
      end

      # Swaps the cartridge for the one at `path`, which power cycles the
      # machine, and says whether it went in.
      def attach_cartridge(path)
        @problem = ""
        Media.attach(@computer, path)
        true
      rescue ArgumentError, SystemCallError, Storage::CRTFile::FormatError, Cartridge::UnsupportedTypeError => e
        @problem = e.message
        false
      end

      # The name the cartridge in the expansion port gives itself, or an
      # empty one.
      def cartridge_name
        cartridge = @computer.address_bus.cartridge
        cartridge.nil? ? "" : cartridge.name
      end

      # Takes the cartridge out with the power off.
      def remove_cartridge
        @computer.address_bus.detach_cartridge
        @computer.power_cycle!
      end

      # A new machine started on `path`, as the command line would, or nil
      # when it won't start.
      def start(options, path)
        @problem = ""
        computer = Frontend.start(options, path, @writable)
        @disk_path = PauseMenu.disk_path(path)
        computer
      rescue ArgumentError, SystemCallError, Media::TrueDrive::Error, Storage::SIDFile::FormatError,
             Storage::T64::FormatError, Storage::TAP::FormatError, Storage::CRTFile::FormatError,
             Storage::G64Image::FormatError, Cartridge::UnsupportedTypeError => e
        @problem = e.message
        nil
      end
    end
  end
end
