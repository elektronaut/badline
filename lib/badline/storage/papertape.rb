# frozen_string_literal: true

module Badline
  module Storage
    # A MOS papertape, the .ptp or .pap the KIM-1 monitor's Q command
    # punches and its L command reads (User Manual, appendix F). Each
    # record is a semicolon, then in hex its count of data bytes, its
    # address, high byte first, the bytes and a 16-bit checksum, the sum
    # of every byte before it, high byte first. The last record has a
    # count of 0, the number of records before it where the address goes,
    # and its checksum, which the monitor checks without counting the
    # records. What comes between records, a line's end, NULs
    # and the XOFF that ends a dump, the monitor skips, as this does.
    class Papertape
      class FormatError < StandardError; end

      # One record's data: its bytes and where they go.
      class Record
        attr_reader :address, :bytes

        def initialize(address, bytes)
          @address = address
          @bytes = bytes
        end
      end

      HEX = "0123456789ABCDEFabcdef"

      # The Records, in the tape's order.
      attr_reader :records

      # The tape's text from its start to the last record's end, which a
      # teletype sends for the L command.
      attr_reader :text

      def self.read(path) = new(File.binread(path))

      def initialize(text)
        @records = []
        @text = text.b
        @position = 0
        read_records
      end

      # Where the first record goes.
      def start_address = @records.first.address

      private

      def read_records
        loop do
          start = @text.index(";", @position)
          raise FormatError, "no last record" if start.nil?

          @position = start + 1
          count = byte
          address = word
          data = Array.new(count) { byte }
          check(count, address, data)
          return finish if count.zero?

          @records << Record.new(address, data)
        end
      end

      def check(count, address, data)
        sum = (count + (address >> 8) + (address & 0xff) + data.sum) & 0xffff
        raise FormatError, "bad checksum in the record at $#{address.to_s(16).rjust(4, '0')}" unless word == sum
      end

      def finish
        raise FormatError, "no records" if @records.empty?

        @text = @text[0, @position]
      end

      def byte
        digits = @text[@position, 2].to_s
        unless digits.size == 2 && HEX.include?(digits[0]) && HEX.include?(digits[1])
          raise FormatError, "not a hex byte at offset #{@position}"
        end

        @position += 2
        digits.to_i(16)
      end

      def word = (byte << 8) | byte
    end
  end
end
