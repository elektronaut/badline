# frozen_string_literal: true

module Badline
  module Media
    AUTOSTART = %(lO"*",8,1\rrun\r)
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
