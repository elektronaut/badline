# frozen_string_literal: true

module Badline
  module Snapshot
    # The BADLINE module badline 0.13 and earlier saved the machine in, a
    # positional layout only the version that wrote it reads. All that is
    # left of it is reading which version that was, for the refusal
    # (Image#load).
    #
    # The payload is deflated. Inside, a little-endian 32-bit length leads
    # a run of BER-compressed integers (Ruby's pack "w"): the number of
    # values and of strings, each string's length, then the values. The
    # strings follow, one after another: the family's marker first, then
    # the badline version.
    module MachineState
      NAME = "BADLINE"

      module_function

      # The badline version that saved the module, or an empty string when
      # it is too damaged to say.
      def written_by(section)
        bytes = Zlib.inflate(section.data)
        return "" if bytes.bytesize < 4

        length = bytes.byteslice(0, 4).unpack1("V").to_i
        numbers = bytes.byteslice(4, length).to_s.unpack("w*").map(&:to_i)
        string_count = numbers.fetch(1, 0)
        return "" if string_count < 2 || numbers.length < 4

        pos = 4 + length + numbers[2]
        bytes.byteslice(pos, numbers[3]).to_s
      rescue Zlib::Error
        ""
      end
    end
  end
end
