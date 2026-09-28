# frozen_string_literal: true

require "badline/media/true_drive"

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
      # With a true drive on device 8 (TrueDrive.plug), a .d64 goes into it
      # instead of the KERNAL traps, and the autostart loads through it.
      def attach(computer, path, autostart: true, song: nil, **options)
        if TrueDrive.takes?(computer, path)
          attach_true_drive(computer, path, autostart:)
        elsif File.directory?(path)
          computer.mount(Storage::HostDirectory.new(path))
          "Mounted #{path} as device 8"
        elsif File.extname(path).downcase == ".crt"
          attach_cartridge(computer, path, options.fetch(:cartridge, {}))
        elsif File.extname(path).downcase == ".sid"
          attach_sid(computer, path, autostart:, song:)
        elsif File.extname(path).downcase == ".tap"
          attach_tape(computer, path, autostart:)
        elsif MOUNT_TYPES.key?(File.extname(path).downcase)
          attach_storage(computer, path, options.fetch(:disk, {}), autostart:)
        else
          attach_prg(computer, path, autostart:)
        end
      end

      # Swaps the disk in device 8 for a disk image or a host directory,
      # while the machine runs, without loading anything. The drive keeps
      # its RAM and its status. `read_only` inserts a disk image
      # write-protected. With a true drive on device 8, the disk goes into
      # that.
      def insert_disk(computer, path, read_only: false)
        return TrueDrive.insert(computer, path) if TrueDrive.drive(computer)

        raise ArgumentError, "#{path} is not a disk image or a directory" unless disk?(path)

        computer.mount(open_storage(path, { read_only: }))
        "Inserted #{path} in device 8"
      end

      # The SID a machine for `path` should be built with. A .sid tune names
      # its own; everything else gets the 6581.
      def sid_model(path)
        return :mos6581 unless path && File.extname(path).downcase == ".sid"

        Storage::SIDFile.new(path).sid_model
      end

      private

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

      def attach_sid(computer, path, autostart:, song:)
        tune = Storage::SIDFile.new(path)
        song = (song || tune.start_song).clamp(1, tune.songs)
        computer.on_init { start_tune(computer, tune, autostart:, song:) }
        title = tune.name.empty? ? path : tune.name
        title += " (song #{song})" if tune.songs > 1
        autostart ? "Playing #{title}" : "Loaded #{title}"
      end

      def start_tune(computer, tune, autostart:, song:)
        computer.ram.write(tune.load_address, tune.data)
        tune.boot_memory(song:).each { |address, bytes| computer.ram.write(address, bytes) }
        computer.type_text(tune.boot_command) if autostart
      end

      def attach_tape(computer, path, autostart:)
        computer.datasette.insert(Storage::TAP.new(path))
        computer.datasette.play!
        computer.type_text(TAPE_AUTOSTART) if autostart
        "Inserted #{path} in the datasette"
      end

      def attach_true_drive(computer, path, autostart:)
        message = TrueDrive.insert(computer, path)
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
        # of it, where BASIC keeps the zero before its first line.
        return unless autostart && (load_addr == BASIC_START || load_addr == BASIC_START - 1)

        # The end of the program, where BASIC's variables start, and where
        # the KERNAL's LOAD leaves its end address.
        end_addr = load_addr + data.length - 2
        [0x2d, 0xae].each { |pointer| computer.ram.write(pointer, [end_addr & 0xff, end_addr >> 8]) }
        computer.type_text("run\r")
      end
    end
  end
end
