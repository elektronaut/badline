# frozen_string_literal: true

module Badline
  module Frontend
    # What the pause menu puts in the machine and takes out: disks, tapes
    # and cartridges, whether disks are writable, which carries over from
    # one disk to the next, and the set of the disk in device 8, which
    # PREVIOUS and NEXT step through: the .m3u or .vfl list it came from,
    # while that lists it, or the set DiskSet finds. It keeps what last went
    # wrong for the page to show.
    class MenuMedia
      attr_reader :problem
      attr_writer :computer

      # Takes the disk set from the command line's `media_path` when it's a
      # list.
      def initialize(media_path, writable)
        @list = Media::DiskList.list?(media_path) ? media_path : ""
        @writable = writable
        @set_path = ""
        @set = []
        @problem = ""
        @computer = nil
      end

      def writable? = @writable

      # The expanded path of the disk in device 8, however it went in, or
      # an empty one.
      def disk_path
        drive = @computer.drive1541
        unless drive.nil?
          disk = drive.disk
          return disk.nil? ? "" : disk.path.to_s
        end

        path = @computer.mounted_path
        path.empty? ? path : File.expand_path(path)
      end

      def inserted?
        drive = @computer.drive1541
        drive.nil? ? @computer.mounted? : !drive.disk.nil?
      end

      # Puts a disk in device 8 or a tape in the datasette, `kind` :disk or
      # :tape, and says whether it went in. A list puts its first disk in.
      def insert(kind, path)
        @problem = ""
        if kind == :disk
          disk = Media::DiskList.disk(path)
          Media.insert_disk(@computer, disk, read_only: !@writable)
          list(path)
        else
          @computer.datasette.insert(Storage::TAP.new(path))
        end
        true
      rescue ArgumentError, SystemCallError, Storage::TAP::FormatError, Storage::T64::FormatError,
             Storage::G64Image::FormatError => e
        @problem = e.message
        false
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
      end

      # Sets whether disks are writable, for the disk in the drive too,
      # which goes in again as the notch now says.
      def writable(writable)
        @writable = writable
        path = disk_path
        insert(:disk, path) if inserted? && !path.empty?
      end

      # The disks of the set the disk in the drive belongs to.
      def disk_set
        path = disk_path
        return [] if path.empty?

        unless @set_path == path
          listed = @list.empty? ? [] : expanded(Media::DiskList.disks(@list))
          @set = listed.include?(path) ? listed : expanded(Media::DiskSet.around(path))
          @set_path = path
        end
        @set
      end

      # Puts the disk `step` before or after this one in its set in the
      # drive, if there is one.
      def step_disk(step)
        set = disk_set
        index = set.index(disk_path)
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

      # What a save of the machine is named after: the cartridge, the disk,
      # the tape, or BASIC, without the bracketed parts of a file's name. A
      # VIC-20's are named after its disk, or else the machine.
      def game_name
        vic20 = @computer.family == :vic20
        name = vic20 ? "" : cartridge_name
        disk = disk_path
        name = File.basename(disk, File.extname(disk)) if name.empty? && !disk.empty?
        name = tape_name if name.empty? && !vic20
        name = name.sub(/\s*[(\[].*\z/, "").strip
        return name unless name.empty?

        vic20 ? "VIC-20" : "BASIC"
      end

      def tape_name
        tape = @computer.datasette.tape
        tape.nil? ? "" : File.basename(tape.path, File.extname(tape.path))
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
        list(path)
        computer
      rescue ArgumentError, SystemCallError, Media::TrueDrive::Error, Storage::SIDFile::FormatError,
             Storage::T64::FormatError, Storage::TAP::FormatError, Storage::CRTFile::FormatError,
             Storage::G64Image::FormatError, Cartridge::UnsupportedTypeError => e
        @problem = e.message
        nil
      end

      private

      # Keeps `path` as the list the set comes from, if it's a list.
      def list(path)
        return unless Media::DiskList.list?(path)

        @list = path
        @set_path = ""
      end

      def expanded(paths) = paths.map { |path| File.expand_path(path) }
    end
  end
end
