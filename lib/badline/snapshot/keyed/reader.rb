# frozen_string_literal: true

module Badline
  module Snapshot
    module Keyed
      # Parses a module's records into one Hash per type, so every value
      # read has a single type in Spinel. Each read takes the current value
      # as its default, which in a machine built for the load is power-on,
      # and returns it when the record is missing or of another type.
      #
      # A Reader with no records stands in for a module the snapshot
      # doesn't have, so every load takes the same path.
      class Reader
        # The tag of each key the module's records hold.
        attr_reader :name, :tags

        # Whether it stands in for a module the snapshot doesn't have.
        def missing? = @missing

        # The records in `section`, which must be in this encoding.
        def self.parse(section)
          unless section.major == MAJOR
            raise FormatError, "#{section.name} #{section.version} was written by a newer badline's encoding, " \
                               "and this one reads #{MAJOR}.#{MINOR}"
          end

          new(section.name, Zlib.inflate(section.data))
        rescue Zlib::Error => e
          raise FormatError, "#{section.name} is damaged: #{e.message}"
        end

        # Stands in for a module the snapshot doesn't have.
        def self.missing(name) = new(name, "".b, missing: true)

        def initialize(name, payload = "".b, missing: false)
          @name = name
          @missing = missing
          @ints = {}
          @bools = {}
          @bytes = {}
          @lists = {}
          @texts = {}
          @tags = {}
          @read = {}
          @adjusted = []
          @unknown_tags = 0
          parse(Cursor.new(payload, name))
        end

        def int(key, default) = fetch_int(key, default)

        def word(key, default) = fetch_masked(key, default, 0xffff)

        def byte(key, default) = fetch_masked(key, default, 0xff)

        # An int cut to the bits a latch holds, reported if it was wider.
        def masked(key, default, mask) = fetch_masked(key, default, mask)

        def bool(key, default) = present?(key, "a bool", @bools.key?(key)) ? @bools.fetch(key) : default

        # Nil when the record is missing.
        def optional_int(key) = present?(key, "an int", @ints.key?(key)) ? @ints.fetch(key) : nil

        def ints(key, default) = present?(key, "a list of ints", @lists.key?(key)) ? @lists.fetch(key) : default

        # A binary String.
        def bytes(key, default) = fetch_bytes(key, default)

        # Reads a hardware array into `array` in place. A shorter list
        # leaves the rest as it was and a longer one is cut, and both are
        # reported.
        def ints_into(key, array)
          return array unless present?(key, "a list of ints", @lists.key?(key))

          fill(key, array, @lists.fetch(key))
        end

        def bytes_into(key, array)
          return array unless present?(key, "bytes", @bytes.key?(key))

          fill(key, array, @bytes.fetch(key).bytes)
        end

        def text(key, default) = fetch_text(key, default)

        # The text, if it is one of `names`, and otherwise `default`,
        # reported.
        def choice(key, names, default)
          value = fetch_text(key, default)
          return value if names.include?(value)

          @adjusted << "#{key} #{value.inspect} is not one of #{names.join(', ')}, left at #{default}"
          default
        end

        # Reports something a unit's load left out or changed beyond one
        # field, such as a line batch from another renderer.
        def adjust(line)
          @adjusted << line
          self
        end

        # The keys of records nothing read.
        def unknown = @tags.keys.reject { |key| @read.key?(key) }

        def report
          Report.new(name:, missing: @missing, unknown:, adjusted: @adjusted.dup, unknown_tags: @unknown_tags)
        end

        private

        def fetch_int(key, default) = present?(key, "an int", @ints.key?(key)) ? @ints.fetch(key) : default

        def fetch_masked(key, default, mask)
          value = fetch_int(key, default)
          return value if value & mask == value

          @adjusted << "#{key} #{value} is wider than its latch, masked to #{value & mask}"
          value & mask
        end

        def fetch_bytes(key, default) = present?(key, "bytes", @bytes.key?(key)) ? @bytes.fetch(key) : default

        def fetch_text(key, default) = present?(key, "text", @texts.key?(key)) ? @texts.fetch(key) : default

        # Whether the key has a record of the type read, `there`. A record
        # of another type counts as missing, and is reported.
        def present?(key, type, there)
          @read[key] = true if there || @tags.key?(key)
          @adjusted << "#{key} is not #{type}, left at its default" if !there && @tags.key?(key)
          there
        end

        def fill(key, array, values)
          unless values.length == array.length
            what = values.length < array.length ? "the rest left as they were" : "the rest cut"
            @adjusted << "#{key} holds #{values.length} values where #{array.length} fit, #{what}"
          end
          [values.length, array.length].min.times { |index| array[index] = values[index] }
          array
        end

        def parse(cursor)
          until cursor.done?
            key = cursor.take(cursor.ber)
            tag = cursor.take(1).getbyte(0).to_i
            store(key, tag, cursor.take(cursor.ber))
          end
        end

        def store(key, tag, value)
          unless tag.between?(INT, TEXT)
            @unknown_tags += 1
            return
          end

          forget(key)
          @tags[key] = tag
          case tag
          when INT then @ints[key] = Cursor.new(value, "#{@name} #{key}").int
          when BOOL then @bools[key] = value.getbyte(0).to_i != 0
          when BYTES then @bytes[key] = value
          when INTS then @lists[key] = list(Cursor.new(value, "#{@name} #{key}"))
          else @texts[key] = value.force_encoding(Encoding::UTF_8)
          end
        end

        def forget(key)
          return unless @tags.key?(key)

          @adjusted << "#{key} appears more than once, the last one counts"
          @ints.delete(key)
          @bools.delete(key)
          @bytes.delete(key)
          @lists.delete(key)
          @texts.delete(key)
        end

        def list(cursor)
          count = cursor.ber
          raise FormatError, "#{@name} ends early, in a list of #{count}" if count > cursor.remaining

          Array.new(count) { cursor.int }
        end
      end
    end
  end
end
