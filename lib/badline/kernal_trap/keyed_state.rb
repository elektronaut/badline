# frozen_string_literal: true

module Badline
  module KernalTrap
    class DOS
      class Channel
        # A channel's fields under `prefix`: whether it is a buffer in the
        # drive's RAM, where it starts and ends, the pointer, the byte it
        # leads with and its buffer's number, the error it reports once its
        # bytes run out, and a file's bytes.
        def save_fields(out, prefix)
          out.text("#{prefix}kind", "channel").bool("#{prefix}writable", @writable).int("#{prefix}base", @base)
          out.int("#{prefix}length", @length).int("#{prefix}pointer", @pointer).optional_int("#{prefix}lead", @lead)
          out.optional_int("#{prefix}buffer", @buffer)
          error = @error
          out.ints("#{prefix}error", error) if error
          out.bytes("#{prefix}bytes", @bytes) unless @writable
        end

        # A buffer channel's bytes are the drive's `ram`.
        def load_fields(input, prefix, ram)
          @writable = input.bool("#{prefix}writable", false)
          @base = input.int("#{prefix}base", 0)
          @length = input.int("#{prefix}length", 0)
          @pointer = input.int("#{prefix}pointer", 0)
          @lead = input.optional_int("#{prefix}lead")
          @buffer = input.optional_int("#{prefix}buffer")
          error = input.ints("#{prefix}error", [])
          @error = error.empty? ? nil : error.dup
          @bytes = @writable ? ram : input.bytes("#{prefix}bytes", "".b).bytes
          self
        end
      end

      class WriteFile
        # A file open for writing, under `prefix`: its name, type and mode,
        # the bytes written so far and the byte held back.
        def save_fields(out, prefix)
          out.text("#{prefix}kind", "write_file").bytes("#{prefix}name", @name.b).text("#{prefix}type", @type.to_s)
          out.text("#{prefix}mode", @mode.to_s).bytes("#{prefix}bytes", @bytes).optional_int("#{prefix}held", @buffer)
        end

        def self.from_fields(input, prefix)
          type = input.choice("#{prefix}type", TYPES.map(&:to_s), "prg")
          mode = input.choice("#{prefix}mode", MODES.map(&:to_s), "write")
          new(input.bytes("#{prefix}name", "".b), TYPES.find { |each| each.to_s == type } || :prg,
              mode: MODES.find { |each| each.to_s == mode } || :write).tap do |file|
            file.load_fields(input, prefix)
          end
        end

        def load_fields(input, prefix)
          @bytes = input.bytes("#{prefix}bytes", "".b).bytes
          @buffer = input.optional_int("#{prefix}held")
        end
      end

      class Channels
        # The channels open, by secondary address, each under channel<SA>.
        def save_fields(out)
          out.ints("channels", @channels.keys)
          @channels.each { |secondary, channel| channel.save_fields(out, "channel#{secondary}.") }
        end

        def load_fields(input, ram)
          @channels.clear
          input.ints("channels", []).each do |secondary|
            @channels[secondary] = Channels.channel_from_fields(input, "channel#{secondary}.", ram)
          end
        end

        def self.channel_from_fields(input, prefix, ram)
          return WriteFile.from_fields(input, prefix) if input.text("#{prefix}kind", "channel") == "write_file"

          Channel.new.load_fields(input, prefix, ram)
        end
      end

      class Status
        # The error channel, under status.
        def save_fields(out) = @channel.save_fields(out, "status.")

        def load_fields(input)
          input.choice("status.kind", ["channel"], "channel")
          @channel = Channel.new.load_fields(input, "status.", [])
        end
      end

      class Memory
        # The drive's RAM, and whether the BAM has been read.
        def save_fields(out)
          out.bytes("ram", @ram).bool("bam", @bam)
        end

        def load_fields(input)
          input.bytes_into("ram", @ram)
          @bam = input.bool("bam", @bam)
        end
      end

      # The storage device 8 serves.
      attr_reader :storage

      # The DOS's fields in a keyed snapshot module (BL-TRAPDOS), after the
      # storage's under storage.*: its RAM, the error channel and the
      # channels open.
      def save_fields(out)
        @memory.save_fields(out)
        @status.save_fields(out)
        @channels.save_fields(out)
      end

      def load_fields(input)
        @memory.load_fields(input)
        @status.load_fields(input)
        @channels.load_fields(input, @memory.ram)
      end
    end

    class Serial
      # The serial trap's fields under `prefix`: whether device 8 listens
      # or talks, on which channel, the frame it is in and the bytes it has
      # gathered.
      def save_fields(out, prefix)
        out.bool("#{prefix}listening", @listening).bool("#{prefix}talking", @talking)
        out.optional_int("#{prefix}listen_channel", @listen_channel)
        out.optional_int("#{prefix}talk_channel", @talk_channel).int("#{prefix}frame", @frame)
        out.bytes("#{prefix}buffer", @buffer)
      end

      def load_fields(input, prefix)
        @listening = input.bool("#{prefix}listening", @listening)
        @talking = input.bool("#{prefix}talking", @talking)
        @listen_channel = input.optional_int("#{prefix}listen_channel")
        @talk_channel = input.optional_int("#{prefix}talk_channel")
        @frame = input.int("#{prefix}frame", @frame)
        @buffer = input.bytes("#{prefix}buffer", "".b).bytes
      end
    end

    class Save
      # Whether a SAVE is under way, under `prefix`.
      def save_fields(out, prefix) = out.bool("#{prefix}saving", @saving)

      def load_fields(input, prefix)
        @saving = input.bool("#{prefix}saving", @saving)
      end
    end
  end
end
