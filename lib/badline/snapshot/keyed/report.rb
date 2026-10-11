# frozen_string_literal: true

module Badline
  module Snapshot
    module Keyed
      # What reading a module left out or changed: whether the snapshot
      # had the module at all, the keys nothing read, a line for each value
      # read other than as written, and how many records had a tag this
      # badline doesn't know.
      Report = Data.define(:name, :missing, :unknown, :adjusted, :unknown_tags) do
        # Lines for the user. A missing module and adjusted values always
        # get one, and unknown keys and tags only when `verbose`, since a
        # snapshot from a later badline has them on every load.
        def lines(verbose: false)
          lines = missing ? ["#{name} is missing, left at power-on"] : []
          lines.concat(adjusted.map { |line| "#{name}: #{line}" })
          return lines unless verbose

          lines << "#{name}: #{unknown.length} unknown field(s): #{unknown.join(', ')}" unless unknown.empty?
          lines << "#{name}: #{unknown_tags} field(s) of an unknown type, skipped" if unknown_tags.positive?
          lines
        end
      end
    end
  end
end
