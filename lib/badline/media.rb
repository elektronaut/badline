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
require "badline/media/tune"
require "badline/media/program"

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
      # (DiskList). Every machine takes each kind of medium the same way,
      # except that the VIC-20 (Vic20Media) has cartridges, programs and a
      # disk autostart of its own, and takes no .sid tunes. The C128 in C64
      # mode takes a C64's.
      def attach(computer, path, autostart: true, subtune: nil, **)
        path = DiskList.disk(path)
        if computer.family == :vic20 && Vic20Media::UNSUPPORTED.include?(File.extname(path).downcase)
          raise ArgumentError, "#{path} doesn't go in a VIC-20"
        end

        BootDisk.attach(computer, path, **) || attach_kind(computer, path, autostart:, subtune:, **)
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

      # What the medium at `path` is to `computer`, which attach goes by:
      # :true_drive for a disk that goes in a true drive (TrueDrive),
      # :directory, :storage for a disk image or a .t64 that the traps
      # mount, :cartridge, :tune, :tape, and :program for anything else.
      def kind(computer, path)
        return :true_drive if TrueDrive.takes?(computer, path)
        return :directory if File.directory?(path)

        extension = File.extname(path).downcase
        return :storage if MOUNT_TYPES.key?(extension)

        case extension
        when ".crt" then :cartridge
        when ".sid" then :tune
        when ".tap" then :tape
        else :program
        end
      end

      # What device 8 serves through the traps for a host directory, a disk
      # image or a .t64. Disk images take the `disk` options. A .t64 is
      # read-only whatever it's given.
      def open_storage(path, disk = {})
        return Storage::HostDirectory.new(path) if File.directory?(path)

        storage = MOUNT_TYPES.fetch(File.extname(path).downcase)
        storage < Storage::DiskImage ? storage.new(path, **disk) : storage.new(path)
      end

      # A program file's bytes, unwrapped from a .p00.
      def program_bytes(path)
        bytes = File.binread(path).bytes
        Storage::P00.wraps?(bytes) ? Storage::P00.data(bytes) : bytes
      end

      private

      def attach_kind(computer, path, autostart:, subtune:, **options)
        disk = options.fetch(:disk, {})
        case kind(computer, path)
        when :true_drive then attach_true_drive(computer, path, disk, autostart:)
        when :directory then mount(computer, path, disk, autostart: false)
        when :storage then mount(computer, path, disk, autostart:)
        when :cartridge then attach_cartridge(computer, path, options.fetch(:cartridge, {}))
        when :tune then Tune.attach(computer, path, autostart:, subtune:)
        when :tape then attach_tape(computer, path, autostart:)
        else attach_prg(computer, path, autostart:)
        end
      end

      def disk?(path)
        storage = MOUNT_TYPES[File.extname(path).downcase]
        File.directory?(path) || (!storage.nil? && storage < Storage::DiskImage)
      end

      def attach_true_drive(computer, path, disk, autostart:)
        message = TrueDrive.insert(computer, path, read_only: disk.fetch(:read_only, false))
        computer.type_text(disk_autostart(computer) { Vic20Media.first_program(path) }) if autostart
        message
      end

      def mount(computer, path, disk, autostart:)
        storage = open_storage(path, disk)
        computer.mount(storage)
        computer.type_text(disk_autostart(computer) { storage.read_file("*") }) if autostart
        "Mounted #{path} as device 8"
      end

      # What loads and runs the first program on the disk in device 8. A
      # VIC-20 goes by that program, which the block gives
      # (Vic20Media.disk_autostart).
      def disk_autostart(computer)
        computer.family == :vic20 ? Vic20Media.disk_autostart(yield) : AUTOSTART
      end

      # A VIC-20 cartridge is its ROM chips.
      def attach_cartridge(computer, path, options)
        if computer.family == :vic20
          computer.attach_cartridge(Storage::CRTFile.new(path, machine: :vic20).chips)
        else
          computer.attach_cartridge(Cartridge.from_file(path, **options))
        end
        "Attached cartridge #{path}"
      end

      # A VIC-20 says when the tape was made for another machine
      # (Vic20Media.tape_message).
      def attach_tape(computer, path, autostart:)
        tape = Storage::TAP.new(path)
        computer.datasette.insert(tape)
        computer.datasette.play!
        computer.type_text(TAPE_AUTOSTART) if autostart
        message = "Inserted #{path} in the datasette"
        computer.family == :vic20 ? Vic20Media.tape_message(tape, message) : message
      end

      # A VIC-20 has programs of its own (Vic20Media.attach_program).
      def attach_prg(computer, path, autostart:)
        bytes = program_bytes(path)
        return Vic20Media.attach_program(computer, path, bytes, autostart:) if computer.family == :vic20

        computer.on_init { Program.load(computer, bytes, autostart:) }
        "Loading #{path}"
      end
    end
  end
end
