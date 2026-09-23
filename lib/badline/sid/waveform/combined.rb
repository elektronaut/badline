# frozen_string_literal: true

module Badline
  class SID
    class Waveform
      # The shapes the chip puts out when more than one waveform is selected.
      #
      # Selecting several shapers connects their outputs to the same twelve
      # DAC lines. Each line settles somewhere between the levels the
      # shapers drive it to, and couples to the lines around it through the
      # resistances between them, so a bit reads high only when enough of
      # its own drive and its neighbours' is high. Modelled here as a
      # threshold on a weighted sum: each selected shaper adds its bit times
      # its strength, a high pulse adds its strength to every line, and the
      # neighbours contribute with one weight per distance below and one per
      # distance above.
      #
      # A low pulse grounds every line.
      #
      # The parameters come from bin/sidwavefit, fitted against OSC3 dumps of
      # real chips in SID/resid-test (oscsample0/1-6581/8580wf30/50/60/70).
      # The tables are built from them once per chip model.
      module Combined
        BITS = 12

        # Per chip and selection (triangle $1, sawtooth $2, pulse $4): the
        # triangle's strength next to a sawtooth (the sawtooth, or a lone
        # triangle, has strength 1), the pulse's strength, the threshold as
        # a fraction of the full drive, then the weights of the lines one to
        # eleven bits below and one to eleven bits above.
        PARAMETERS = {
          mos6581: {
            0x3 => [0.522, 6.4087, 0.9062,
                    0.5304, 0.278, 0.1473, 0.0773, 0.0, 0.0184, 0.0113, 0.0251, 0.0594, 0.2001, 0.2001,
                    0.4103, 0.1756, 0.0687, 0.0282, 0.0115, 0.0047, 0.0031, 0.2001, 0.2001, 0.2001, 0.2001],
            0x5 => [5.871, 0.0, 0.7485,
                    0.6522, 0.5913, 0.5404, 0.4828, 0.428, 0.361, 0.2955, 0.2453, 0.1558, 0.0501, 0.0016,
                    0.7106, 0.6667, 0.6426, 0.6376, 0.5761, 0.6639, 0.7193, 0.4728, 0.4306, 0.392, 0.357],
            0x6 => [3.8329, 4.7751, 0.9565,
                    0.815, 0.8302, 0.8204, 0.8107, 0.8511, 0.8416, 0.8322, 0.8728, 0.8636, 0.8545, 0.8954,
                    0.8071, 0.7979, 0.7465, 0.7771, 0.7643, 0.7572, 0.7054, 0.4585, 0.4159, 0.3773, 0.3421],
            0x7 => [5.5703, 0.2543, 0.9575,
                    0.7177, 0.515, 0.3696, 0.2653, 0.1904, 0.1367, 0.0606, 0.0953, 0.0506, 0.0363, 0.2261,
                    0.6347, 0.286, 0.203, 0.0817, 0.0438, 0.1235, 0.2001, 0.2001, 0.2001, 0.2001, 0.2001]
          },
          mos8580: {
            0x3 => [0.2223, 7.7741, 0.8869,
                    0.4626, 0.2025, 0.0911, 0.041, 0.0185, 0.0, 0.0008, 0.0, 0.0, 0.0127, 0.0063,
                    0.5633, 0.311, 0.2099, 0.0881, 0.0255, 0.0, 0.0431, 0.2002, 0.2002, 0.2002, 0.2002],
            0x5 => [3.1022, 1.1282, 0.9157,
                    0.2731, 0.2748, 0.0031, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                    0.6228, 0.7375, 0.6094, 0.6667, 0.4381, 0.4714, 0.3648, 0.2669, 0.2264, 0.2001, 0.2001],
            0x6 => [0.9477, 0.0012, 0.7837,
                    0.2565, 0.2289, 0.1095, 0.0805, 0.0282, 0.0281, 0.0, 0.0, 0.0, 0.0, 0.0063,
                    0.3382, 0.3131, 0.3129, 0.2898, 0.233, 0.1762, 0.2135, 0.2002, 0.2002, 0.2002, 0.2002],
            0x7 => [1.219, 1.1111, 0.9473,
                    0.3829, 0.1466, 0.0577, 0.0215, 0.0082, 0.0032, 0.0, 0.0, 0.0, 0.0, 0.0,
                    0.7273, 0.6845, 0.566, 0.4807, 0.6, 0.1954, 0.4651, 0.2194, 0.2002, 0.2002, 0.2002]
          }
        }.freeze

        # A compiled parameter set: the weight matrix, and per line the sum
        # of its weights and the threshold against the full drive.
        class Network
          attr_reader :triangle_strength, :pulse_strength

          def initialize(params)
            @triangle_strength, @pulse_strength, threshold = params[0, 3]
            below = [1.0] + params[3, BITS - 1]
            above = [1.0] + params[3 + BITS - 1, BITS - 1]
            @weights = Array.new(BITS) do |i|
              Array.new(BITS) { |j| j <= i ? below[i - j] : above[j - i] }.freeze
            end.freeze
            @norms = @weights.map(&:sum).freeze
            @threshold = threshold
          end

          # `drives` holds [bits, strength] for each selected shaper; a high
          # pulse is passed separately, as it drives every line alike.
          def shape(drives, pulse)
            total = drives.sum { |_, strength| strength }
            total += @pulse_strength if pulse
            out = 0
            BITS.times do |i|
              level = pulse ? @pulse_strength * @norms[i] : 0.0
              weights = @weights[i]
              drives.each do |bits, strength|
                BITS.times { |j| level += weights[j] * strength if bits[j] == 1 }
              end
              out |= 1 << i if level >= @threshold * @norms[i] * total
            end
            out
          end
        end

        module_function

        # The pulse-high shapes of the four combinations without noise.
        def tables(model)
          @tables ||= {}
          @tables[model] ||= PARAMETERS.fetch(model).to_h do |selected, params|
            [selected, table(selected, params)]
          end.freeze
        end

        # One combination's shapes, indexed by the phase (the sawtooth), or
        # for triangle and pulse by the triangle. A triangle combined with a
        # sawtooth is never folded, so it is the phase shifted left one bit.
        def table(selected, params)
          network = Network.new(params)
          Array.new(1 << BITS) do |index|
            triangle = selected == 0x5 ? index : (index << 1) & 0xfff
            network.shape(drives(selected, network, index, triangle), selected.anybits?(0x4))
          end.freeze
        end

        def drives(selected, network, saw, triangle)
          drives = []
          drives << [saw, 1.0] if selected.anybits?(0x2)
          drives << [triangle, selected.anybits?(0x2) ? network.triangle_strength : 1.0] if selected.anybits?(0x1)
          drives
        end
      end
    end
  end
end
