# frozen_string_literal: true

module Badline
  module Snapshot
    module Keyed
      # A Reader that notes every read: the module, the key, the type read
      # and the default passed. Loading a machine at power-on through
      # Recorders lists each module's fields with their power-on values
      # (FieldDoc).
      class Recorder < Reader
        Field = Data.define(:module_name, :key, :type, :default)

        attr_reader :fields

        def initialize(name, payload = "".b, missing: false)
          super
          @fields = []
        end

        def int(key, default)
          note(key, "int", default)
          super
        end

        def word(key, default)
          note(key, "word", default)
          super
        end

        def byte(key, default)
          note(key, "byte", default)
          super
        end

        def masked(key, default, mask)
          note(key, "int & 0x#{mask.to_s(16)}", default)
          super
        end

        def bool(key, default)
          note(key, "bool", default)
          super
        end

        def optional_int(key)
          note(key, "int, optional", nil)
          super
        end

        def ints(key, default)
          note(key, "ints", default.dup)
          super
        end

        def bytes(key, default)
          note(key, "bytes", default.dup)
          super
        end

        def ints_into(key, array)
          note(key, "ints", array.dup)
          super
        end

        def bytes_into(key, array)
          note(key, "bytes", array.dup)
          super
        end

        def text(key, default)
          note(key, "text", default)
          super
        end

        def choice(key, names, default)
          note(key, "text: #{names.join(' ')}", default)
          super
        end

        private

        def note(key, type, default)
          @fields << Field.new(module_name: name, key:, type:, default:)
        end
      end
    end
  end
end
