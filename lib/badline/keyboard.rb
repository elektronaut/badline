# frozen_string_literal: true

module Badline
  # The 8x8 key matrix spanning CIA 1's two ports: rows on port A, columns on
  # port B.
  #
  # A pressed key shorts its row line to its column line, so whichever side is
  # pulled low drags the other down with it. Scanning works in either
  # direction, and chains of keys sharing a line propagate the pulldown -- the
  # ghost keys real hardware reports.
  class Keyboard
    include IntegerHelper

    # Keys the C64 types as a combination: cursor up and cursor left are the
    # shifted cursor keys. Pressing one holds both of its matrix keys, while
    # a shift key held on its own stays down when it is released.
    COMBINATIONS = {
      cursor_up: %i[lshift cursor_v],
      cursor_left: %i[lshift cursor_h]
    }.freeze

    # The C64's wiring: one row of keys per port A line, in port B column
    # order.
    C64_MATRIX = [
      %i[delete return cursor_h f7 f1 f3 f5 cursor_v],
      %i[3 w a 4 z s e lshift],
      %i[5 r d 6 c f t x],
      %i[7 y g 8 b h u v],
      %i[9 i j 0 m k o n],
      %i[+ p l - . : @ ,],
      %i[£ * ; clr_home rshift = up /],
      %i[1 left control 2 space cbm q run_stop]
    ].freeze

    attr_reader :keys, :matrix

    def initialize(matrix: C64_MATRIX)
      @keys = []
      @row_masks = nil
      @matrix = matrix
    end

    def press(key)
      return unless valid_key?(key)

      @keys << key
      @row_masks = nil
    end

    def release(key)
      @keys.reject! { |k| k == key }
      @row_masks = nil
    end

    # Settles the row (port A) and column (port B) lines against each other
    # until no key contact pulls a line low any more, and returns both.
    def scan(rows, cols)
      return [rows, cols] if keys.empty?

      loop do
        settled_rows = rows
        settled_cols = cols

        row_masks.each_with_index do |mask, row|
          bit = 1 << row
          next if mask.zero? || (rows.allbits?(bit) && cols.allbits?(mask))

          rows &= ~bit
          cols &= ~mask
        end

        return [rows, cols] if rows == settled_rows && cols == settled_cols
      end
    end

    def read_a(port_a, port_b) = scan(port_a, port_b).first

    def read_b(port_a, port_b) = scan(port_a, port_b).last

    private

    # Columns held down per row, as a bit mask of port B lines.
    def row_masks
      @row_masks ||= begin
        pressed = held
        matrix.map do |row|
          row.each_with_index.sum { |key, column| pressed.include?(key) ? 1 << column : 0 }
        end
      end
    end

    # The matrix keys held down, with each combination expanded.
    def held
      keys.flat_map { |key| COMBINATIONS[key] || [key] }
    end

    def valid_key?(key)
      COMBINATIONS.key?(key) || matrix.flatten.include?(key)
    end
  end
end
