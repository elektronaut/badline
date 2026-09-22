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
      def attach(computer, path, autostart: true)
        if File.directory?(path)
          computer.mount(Storage::HostDirectory.new(path))
          "Mounted #{path} as device 8"
        elsif File.extname(path).downcase == ".crt"
          attach_cartridge(computer, path)
        elsif File.extname(path).downcase == ".sid"
          attach_sid(computer, path, autostart:)
        elsif File.extname(path).downcase == ".tap"
          attach_tape(computer, path, autostart:)
        elsif (storage = MOUNT_TYPES[File.extname(path).downcase])
          attach_storage(computer, storage.new(path), path, autostart:)
        else
          attach_prg(computer, path, autostart:)
        end
      end

      private

      def attach_cartridge(computer, path)
        computer.attach_cartridge(Cartridge.from_file(path))
        "Attached cartridge #{path}"
      end

      def attach_sid(computer, path, autostart:)
        tune = Storage::SIDFile.new(path)
        computer.on_init { start_tune(computer, tune, autostart:) }
        title = tune.name.empty? ? path : tune.name
        autostart ? "Playing #{title}" : "Loaded #{title}"
      end

      def start_tune(computer, tune, autostart:)
        computer.ram.write(tune.load_address, tune.data)
        computer.ram.write(tune.driver_address, tune.driver)
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
