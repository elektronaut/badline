# frozen_string_literal: true

module Badline
  module Snapshot
    # The BADLINE module: badline's whole machine, for a restore that
    # carries on exactly where the save left off. It starts with the VIC,
    # CIA and SID models the machine was built with, one byte each, then
    # the deflated StateWriter encoding of the Computer. It is only good
    # for the badline version that wrote it, and a restore checks every
    # table and class it names still exists.
    module MachineState
      NAME = "BADLINE"
      MAJOR = 1
      MINOR = 0
      MODELS = [VIC::MODELS, CIA::MODELS, %i[mos6581 mos8580]].freeze
      # Whether the SID's output is recorded, and where to, is the host's
      # business, as the window's sound is: the target keeps its own.
      RECORDING = %i[@synthesizing @decimator @samples @filter_chunk].freeze

      module_function

      def section(computer)
        models = [computer.vic.model, computer.cia1.model, computer.sid.model]
        header = models.each_with_index.map { |model, i| MODELS[i].index(model) }.pack("C3")
        Section.new(name: NAME, major: MAJOR, minor: MINOR,
                    data: header + Zlib.deflate(StateWriter.encode(computer)))
      end

      # The keyword arguments Computer.new takes to build the machine the
      # section was saved from.
      def models(section)
        vic, cia, sid = section.data.unpack("C3").each_with_index.map do |index, i|
          MODELS[i].fetch(index) { raise FormatError, "unknown chip model #{index} in #{NAME}" }
        end
        { vic_model: vic, cia_model: cia, sid_model: sid }
      end

      def restore(section, computer)
        raise FormatError, "#{NAME} #{section.version} is newer than this badline reads" if section.major != MAJOR

        records = StateReader.decode(Zlib.inflate(section.data.byteslice(3..)))
        mount_drive(records, computer)
        insert_cartridge(records, computer)
        keep_recording(computer.sid) { StateRestorer.new(records).restore(computer) }
      rescue Zlib::Error => e
        raise FormatError, "#{NAME} is damaged: #{e.message}"
      end

      # The blocks that wire a drive or a cartridge into the machine can't
      # be written to a file. The target gets the same drive and cartridge
      # first, built the ordinary way, and the restore then puts their
      # state into them.
      def mount_drive(records, computer)
        return unless ivar(records, records.first, :@drive).is_a?(Value::Ref)
        return if computer.instance_variable_get(:@drive)

        computer.mount(Storage::HostDirectory.new(Dir.pwd))
      end

      # A cartridge is built again from the CRT image it keeps. One built
      # from an image the machine can't carry comes back without the
      # blocks that wire its parts together.
      def insert_cartridge(records, computer)
        cartridge = ivar(records, records.first, :@address_bus, :@cartridge)
        return unless cartridge.is_a?(Value::Ref)

        record = records[cartridge.id]
        current = computer.address_bus.cartridge
        return if current.instance_of?(Value.machine_class(record.class_name))

        crt = ivar(records, record, :@crt)
        return unless crt.is_a?(Value::Ref)

        computer.connect_cartridge(Cartridge.from_crt(StateRestorer.new(records).build_value(crt)))
      end

      def keep_recording(sid)
        kept = RECORDING.to_h { |name| [name, sid.instance_variable_get(name)] }
        yield
        kept.each { |name, value| sid.instance_variable_set(name, value) }
        sid.send(:update_span_rules)
      end

      # Follows instance variables from `record` through the records.
      def ivar(records, record, *names)
        names.reduce(record) do |current, name|
          current = records[current.id] if current.is_a?(Value::Ref)
          return nil unless current.respond_to?(:ivars)

          current.ivars.find { |ivar, _| ivar == name }&.last
        end
      end
    end
  end
end
