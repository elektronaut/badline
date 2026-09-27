# frozen_string_literal: true

module Badline
  module Snapshot
    # Decodes what StateWriter wrote into one record per node. References
    # stay Value::Ref, Value::Constant and Value::Host until a StateRestorer
    # resolves them against a machine.
    class StateReader
      include Value

      ArrayRecord = Data.define(:frozen, :items)
      HashRecord = Data.define(:frozen, :identity, :default, :pairs)
      StringRecord = Data.define(:bytes)
      ObjectRecord = Data.define(:class_name, :ivars)
      StructRecord = Data.define(:class_name, :fields, :ivars)
      DataRecord = Data.define(:class_name, :fields)
      ProcRecord = Data.define(:receiver, :locals)
      MethodRecord = Data.define(:receiver, :name)

      def self.decode(bytes) = new(bytes).records

      def initialize(bytes)
        @bytes = bytes.b
        @pos = 0
        @symbols = []
      end

      def records
        records = []
        records << record while @pos < @bytes.bytesize
        records
      end

      private

      def record
        case (kind = byte)
        when ARRAY then array
        when HASH then hash
        when STRING then StringRecord.new(bytes: string)
        when OBJECT then ObjectRecord.new(class_name: string, ivars: pairs)
        when STRUCT then StructRecord.new(class_name: string, fields: pairs, ivars: pairs)
        when DATA then DataRecord.new(class_name: string, fields: pairs)
        when PROC then ProcRecord.new(receiver: value, locals: pairs)
        when METHOD then MethodRecord.new(receiver: value, name: value)
        else raise FormatError, "unknown machine state record #{kind} at byte #{@pos - 1}"
        end
      end

      def array
        frozen = byte == 1
        length = integer
        items = case byte
                when BYTES then take(length).unpack("C*")
                when WORDS then take(length * 4).unpack("l<*")
                else Array.new(length) { value }
                end
        ArrayRecord.new(frozen:, items:)
      end

      def hash
        flags = byte
        default = value
        pairs = Array.new(integer) { [value, value] }
        HashRecord.new(frozen: flags.anybits?(1), identity: flags.anybits?(2), default:, pairs:)
      end

      def pairs = Array.new(integer) { [value, value] }

      def value
        case (tag = byte)
        when NIL_VALUE then nil
        when TRUE_VALUE then true
        when FALSE_VALUE then false
        when INTEGER then integer
        when FLOAT then take(8).unpack1("E")
        else reference(tag)
        end
      end

      def reference(tag)
        case tag
        when SYMBOL then symbol
        when NODE then Ref.new(id: integer)
        when CONSTANT then Constant.new(path: string.force_encoding(Encoding::UTF_8))
        when HOST then HOST_VALUE
        when RANGE then Range.new(value, value, byte == 1)
        when FROZEN_STRING then frozen_string
        when CLASS then machine_class(string.force_encoding(Encoding::UTF_8))
        else raise FormatError, "unknown machine state value #{tag} at byte #{@pos - 1}"
        end
      end

      def symbol
        id = integer
        return @symbols.fetch(id - 1) { raise FormatError, "unknown symbol #{id}" } if id.positive?

        string.force_encoding(Encoding::UTF_8).to_sym.tap { |name| @symbols << name }
      end

      def frozen_string
        encoding = Encoding.find(string)
        string.force_encoding(encoding).freeze
      end

      def string = take(integer)

      def take(length)
        raise FormatError, "machine state ends early" if @pos + length > @bytes.bytesize

        @bytes.byteslice(@pos, length).tap { @pos += length }
      end

      def byte
        raise FormatError, "machine state ends early" if @pos >= @bytes.bytesize

        @bytes.getbyte(@pos).tap { @pos += 1 }
      end

      def integer
        n = 0
        shift = 0
        loop do
          b = byte
          n |= (b & 0x7f) << shift
          break if b < 0x80

          shift += 7
        end
        n.odd? ? -((n + 1) >> 1) : n >> 1
      end
    end
  end
end
