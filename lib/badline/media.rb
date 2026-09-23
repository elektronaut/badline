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
      # `cartridge` sets the jumpers of a .crt cartridge that has them, such
      # as `{ flash_jumper: true }` for the Retro Replay's flash mode.
      def attach(computer, path, autostart: true, song: nil, cartridge: {})
        if File.directory?(path)
          computer.mount(Storage::HostDirectory.new(path))
          "Mounted #{path} as device 8"
        elsif File.extname(path).downcase == ".crt"
          attach_cartridge(computer, path, cartridge)
        elsif File.extname(path).downcase == ".sid"
          attach_sid(computer, path, autostart:, song:)
        elsif File.extname(path).downcase == ".tap"
          attach_tape(computer, path, autostart:)
        elsif (storage = MOUNT_TYPES[File.extname(path).downcase])
          attach_storage(computer, storage.new(path), path, autostart:)
        else
          attach_prg(computer, path, autostart:)
        end
      end

      # The SID a machine for `path` should be built with. A .sid tune names
      # its own; everything else gets the 6581.
      def sid_model(path)
        return :mos6581 unless path && File.extname(path).downcase == ".sid"

        Storage::SIDFile.new(path).sid_model
      end

      private

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
        computer.ram.write(tune.driver_address, tune.driver(song:))
        computer.type_text("sys#{tune.driver_address}\r") if autostart
      end

      def attach_tape(computer, path, autostart:)
        computer.datasette.insert(Storage::TAP.new(path))
        computer.datasette.play!
        computer.type_text(TAPE_AUTOSTART) if autostart
        "Inserted #{path} in the datasette"
      end

      def attach_storage(computer, storage, path, autostart:)
        computer.mount(storage)
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
        # Run only makes sense for programs at BASIC start.
        return unless autostart && load_addr == BASIC_START

        end_addr = load_addr + data.length - 2
        computer.ram.write(0x2d, [end_addr & 0xff, end_addr >> 8])
        computer.type_text("run\r")
      end
    end
  end
end
