# frozen_string_literal: true

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
      def attach(computer, path, autostart: true, song: nil, **options)
        if File.directory?(path)
          computer.mount(Storage::HostDirectory.new(path))
          "Mounted #{path} as device 8"
        elsif File.extname(path).downcase == ".crt"
          attach_cartridge(computer, path, options.fetch(:cartridge, {}))
        elsif File.extname(path).downcase == ".sid"
          attach_sid(computer, path, autostart:, song:)
        elsif File.extname(path).downcase == ".tap"
          attach_tape(computer, path, autostart:)
        elsif g64?(path) || MOUNT_TYPES.key?(File.extname(path).downcase)
          attach_storage(computer, path, options.fetch(:disk, {}), autostart:)
        else
          attach_prg(computer, path, autostart:)
        end
      end

      # Swaps the disk in device 8 for a disk image or a host directory,
      # while the machine runs, without loading anything. The drive keeps
      # its RAM and its status. `read_only` inserts a disk image
      # write-protected.
      #
      # A .g64 goes in a true 1541, which is plugged in as device 8 when
      # there's none yet, and takes out what was mounted through the LOAD
      # trap, so LOAD and SAVE reach the 1541 too. Once a true 1541 is
      # device 8, a .d64 goes in its drive as well, and other disks, which
      # a 1541 can't read, raise ArgumentError.
      def insert_disk(computer, path, read_only: false)
        return insert_drive1541(computer, path, read_only:) if g64?(path) || drive1541?(computer)

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

      def g64?(path) = File.extname(path).downcase == ".g64"

      def drive1541?(computer) = computer.drive1541&.device == KernalTrap::Routine::DEVICE

      def insert_drive1541(computer, path, read_only:)
        unless %w[.d64 .g64].include?(File.extname(path).downcase)
          raise ArgumentError, "#{path} is not a .d64 or .g64 image, which the 1541 reads"
        end

        disk = Drive1541::Disk.open(path, read_only:)
        computer.unmount
        computer.attach_drive1541(Drive1541.new) unless computer.drive1541
        computer.drive1541.insert(disk)
        "Inserted #{path} in the 1541 as device 8"
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

      # A .g64 holds the disk's raw GCR, which only a true drive reads, so
      # attaching one plugs a 1541 in as device 8 when there's none yet.
      def attach_storage(computer, path, disk, autostart:)
        if g64?(path)
          message = insert_drive1541(computer, path, read_only: disk.fetch(:read_only, false))
        else
          computer.mount(open_storage(path, disk))
          message = "Mounted #{path} as device 8"
        end
        computer.type_text(AUTOSTART) if autostart
        message
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
