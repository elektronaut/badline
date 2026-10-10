# frozen_string_literal: true

require "badline/media/true_drive"
require "badline/media/boot_disk"
require "badline/media/not_disk"
require "badline/media/queue"
require "badline/media/disk_set"
require "badline/media/disk_list"
require "badline/media/vic20_basic"
require "badline/media/vic20_cartridge"
require "badline/media/vic20_media"

module Badline
  module Media
    AUTOSTART = %(lO"*",8,1\rrun\r)
    TAPE_AUTOSTART = %(lO\rrun\r)
    BASIC_START = 0x0801

    MOUNT_TYPES = {
      ".d64" => Storage::D64Image,
      ".d71" => Storage::D71Image,
      ".d81" => Storage::D81Image,
      ".t64" => Storage::T64
    }.freeze

    class << self
      # The options are the medium's own. `cartridge:` sets the jumpers of a
      # .crt cartridge that has them, such as `{ flash_jumper: true }` for
      # the Retro Replay's flash mode, and `disk: { read_only: true }` mounts
      # a disk image write-protected, so nothing the program does writes to
      # its file. Media they don't apply to ignore them.
      #
      # A .g64 plugs in a true drive as device 8 (TrueDrive), and with one
      # there, a .d64 goes into it instead of the KERNAL traps too. The
      # autostart then loads through it.
      #
      # On a C128 in C128 mode, a boot disk goes in a true drive for the
      # KERNAL to boot at power-on, with nothing typed (BootDisk).
      #
      # An .m3u or .vfl list of disks attaches the first disk it lists
      # (DiskList). The VIC-20 takes its own media (Vic20Media), and the
      # C128 in C64 mode a C64's.
      def attach(computer, path, autostart: true, subtune: nil, **)
        path = DiskList.disk(path)
        return Vic20Media.attach(computer, path, autostart:, **) if computer.family == :vic20

        BootDisk.attach(computer, path, **) || attach_c64(computer, path, autostart:, subtune:, **)
      end

      # Swaps the disk in device 8 for a disk image or a host directory,
      # while the machine runs, without loading anything. The drive keeps
      # its RAM and its status. `read_only` inserts a disk image
      # write-protected.
      #
      # A .g64 goes in a true 1541, which is plugged in as device 8 when
      # there's none yet (TrueDrive). Once a true 1541 is device 8, a .d64
      # goes in its drive as well, and other disks, which a 1541 can't
      # read, raise TrueDrive::Error, an ArgumentError. Anything else
      # raises NotDisk.
      def insert_disk(computer, path, read_only: false)
        return TrueDrive.insert(computer, path, read_only:) if TrueDrive.takes?(computer, path)

        raise NotDisk, "#{path} is not a disk image or a directory" unless disk?(path)

        computer.mount(open_storage(path, { read_only: }))
        "Inserted #{path} in device 8"
      end

      # The RAM expansion a VIC-20 for `path` should be built with
      # (Vic20Media.ram_for), a key of Vic20::Bus::RAM_CONFIGURATIONS.
      def vic20_ram_for(path) = Vic20Media.ram_for(path)

      # The SID a machine for `path` should be built with. A .sid tune names
      # its own; everything else gets `otherwise`.
      def sid_model(path, otherwise: :mos6581)
        return otherwise unless path && File.extname(path).downcase == ".sid"

        Storage::SIDFile.new(path).sid_model
      end

      private

      def attach_c64(computer, path, autostart:, subtune:, **options)
        if TrueDrive.takes?(computer, path)
          attach_true_drive(computer, path, options.fetch(:disk, {}), autostart:)
        elsif File.directory?(path)
          computer.mount(Storage::HostDirectory.new(path))
          "Mounted #{path} as device 8"
        elsif File.extname(path).downcase == ".crt"
          attach_cartridge(computer, path, options.fetch(:cartridge, {}))
        elsif File.extname(path).downcase == ".sid"
          attach_sid(computer, path, autostart:, subtune:)
        elsif File.extname(path).downcase == ".tap"
          attach_tape(computer, path, autostart:)
        elsif MOUNT_TYPES.key?(File.extname(path).downcase)
          attach_storage(computer, path, options.fetch(:disk, {}), autostart:)
        else
          attach_prg(computer, path, autostart:)
        end
      end

      def disk?(path)
        storage = MOUNT_TYPES[File.extname(path).downcase]
        File.directory?(path) || (!storage.nil? && storage < Storage::DiskImage)
      end

      # Disk images take the `disk` options. A .t64 is read-only whatever
      # it's given.
      def open_storage(path, disk)
        return Storage::HostDirectory.new(path) if File.directory?(path)

        storage = MOUNT_TYPES[File.extname(path).downcase]
        storage < Storage::DiskImage ? storage.new(path, **disk) : storage.new(path)
      end

      def attach_cartridge(computer, path, options)
        computer.attach_cartridge(Cartridge.from_file(path, **options))
        "Attached cartridge #{path}"
      end

      def attach_sid(computer, path, autostart:, subtune:)
        tune = Storage::SIDFile.new(path)
        if tune.sids > 1
          raise Storage::SIDFile::FormatError, "Written for #{tune.sids} SIDs, which only the SID player plays"
        end

        subtune = (subtune || tune.start_subtune).clamp(1, tune.subtunes)
        computer.on_init { start_tune(computer, tune, autostart:, subtune:) }
        title = tune.name.empty? ? path : tune.name
        title += " (subtune #{subtune})" if tune.subtunes > 1
        autostart ? "Playing #{title}" : "Loaded #{title}"
      end

      def start_tune(computer, tune, autostart:, subtune:)
        computer.ram.write(tune.load_address, tune.data)
        tune.boot_memory(subtune:).each { |address, bytes| computer.ram.write(address, bytes) }
        computer.type_text(tune.boot_command) if autostart
      end

      def attach_tape(computer, path, autostart:)
        computer.datasette.insert(Storage::TAP.new(path))
        computer.datasette.play!
        computer.type_text(TAPE_AUTOSTART) if autostart
        "Inserted #{path} in the datasette"
      end

      def attach_true_drive(computer, path, disk, autostart:)
        message = TrueDrive.insert(computer, path, read_only: disk.fetch(:read_only, false))
        computer.type_text(AUTOSTART) if autostart
        message
      end

      def attach_storage(computer, path, disk, autostart:)
        computer.mount(open_storage(path, disk))
        computer.type_text(AUTOSTART) if autostart
        "Mounted #{path} as device 8"
      end

      def attach_prg(computer, path, autostart:)
        bytes = File.binread(path).bytes
        bytes = Storage::P00.data(bytes) if Storage::P00.wraps?(bytes)
        computer.on_init { start_prg(computer, bytes, autostart:) }
        "Loading #{path}"
      end

      def start_prg(computer, data, autostart:)
        load_addr = computer.load_prg(data)
        # Run only makes sense for programs at BASIC start, or a byte ahead
        # of it, where BASIC keeps the zero before its first line. BASIC 7.0
        # starts at $1C01 and keeps the end of its text at $1210.
        start, text_end = computer.family == :c128 && computer.mode == :c128 ? [0x1c01, 0x1210] : [BASIC_START, 0x2d]
        return unless autostart && (load_addr == start || load_addr == start - 1)

        # The end of the program, where BASIC's variables start, and where
        # the KERNAL's LOAD leaves its end address.
        end_addr = load_addr + data.length - 2
        [text_end, 0xae].each { |pointer| computer.ram.write(pointer, [end_addr & 0xff, end_addr >> 8]) }
        computer.type_text("run\r")
      end
    end
  end
end
