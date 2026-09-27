# frozen_string_literal: true

module Badline
  module Snapshot
    # Little-endian fields for VICE modules, written one after another as
    # VICE's SMW_B, SMW_W, SMW_DW, SMW_QW and SMW_BA write them.
    class FieldWriter
      def initialize
        @out = String.new(encoding: Encoding::BINARY)
      end

      def byte(value) = tap { @out << [value & 0xff].pack("C") }
      def word(value) = tap { @out << [value & 0xffff].pack("v") }
      def dword(value) = tap { @out << [value & 0xffff_ffff].pack("V") }
      def qword(value) = tap { @out << [value & 0xffff_ffff_ffff_ffff].pack("Q<") }
      def flag(value) = byte(value ? 1 : 0)

      def bytes(values)
        tap { @out << (values.is_a?(String) ? values.b : values.map { |v| v & 0xff }.pack("C*")) }
      end

      def zeros(count) = tap { @out << ("\0".b * count) }

      def section(name, major, minor) = Section.new(name:, major:, minor:, data: @out.dup)
    end

    # Reads a VICE module's fields in the order they were written.
    class FieldReader
      def initialize(section)
        @section = section
        @data = section.data
        @pos = 0
      end

      def byte = take(1).unpack1("C")
      def word = take(2).unpack1("v")
      def dword = take(4).unpack1("V")
      def qword = take(8).unpack1("Q<")
      def flag? = !byte.zero?
      def bytes(count) = take(count).unpack("C*")
      def skip(count) = tap { take(count) }

      private

      def take(count)
        if @pos + count > @data.bytesize
          raise FormatError, "#{@section.name} #{@section.version} ends early, at byte #{@data.bytesize}"
        end

        @data.byteslice(@pos, count).tap { @pos += count }
      end
    end
  end
end
