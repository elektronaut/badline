# frozen_string_literal: true

# Names where two snapshots differ, module by module, and in the BADLINE
# module's positional State the line of the save_state that wrote each
# value that differs, for bin/snapshot_check.
module SnapshotTracing
  # A StateWriter that notes, for every value and string, the line of the
  # save_state that wrote it.
  class TracingWriter < Badline::Snapshot::StateWriter
    ROOT = "#{File.expand_path('../../lib', __dir__)}/".freeze

    attr_reader :value_sites, :string_sites

    def initialize
      super
      @value_sites = []
      @string_sites = []
    end

    def int(value)
      @value_sites << site
      super
    end

    def boolean(value)
      @value_sites << site
      super
    end

    def blob(values)
      @string_sites << site
      super
    end

    def string(value)
      @string_sites << site
      super
    end

    private

    def site
      location = caller_locations(2).find { |frame| !frame.path.end_with?("snapshot/state.rb") }
      return "?" unless location

      "#{location.path.delete_prefix(ROOT)}:#{location.lineno} #{location.label}"
    end
  end

  # Where two States differ, labelled from `sites` (a TracingWriter of a
  # machine saving the first).
  module StateDiff
    LIMIT = 8

    module_function

    def lines(ours, theirs, sites)
      lines = values(ours.values, theirs.values, sites&.value_sites) +
              strings(ours.strings, theirs.strings, sites&.string_sites)
      lines.first(LIMIT * 2)
    end

    def values(ours, theirs, sites)
      lines = []
      lines << "#{ours.length} values against #{theirs.length}" unless ours.length == theirs.length
      [ours.length, theirs.length].max.times do |index|
        next if ours[index] == theirs[index]

        lines << "value #{index} (#{sites&.at(index) || '?'}): #{ours[index].inspect} against #{theirs[index].inspect}"
        break if lines.length >= LIMIT
      end
      lines
    end

    def strings(ours, theirs, sites)
      lines = []
      lines << "#{ours.length} strings against #{theirs.length}" unless ours.length == theirs.length
      [ours.length, theirs.length].max.times do |index|
        next if ours[index] == theirs[index]

        lines << "string #{index} (#{sites&.at(index) || '?'}): #{string_difference(ours[index], theirs[index])}"
        break if lines.length >= LIMIT
      end
      lines
    end

    def string_difference(ours, theirs)
      return "#{ours.inspect[0, 30]} against #{theirs.inspect[0, 30]}" if ours.nil? || theirs.nil?

      at = (0...[ours.bytesize, theirs.bytesize].min).find { |i| ours.getbyte(i) != theirs.getbyte(i) }
      at ||= [ours.bytesize, theirs.bytesize].min
      "#{ours.bytesize} bytes against #{theirs.bytesize}, first difference at byte #{at} " \
        "(#{ours.getbyte(at).inspect} against #{theirs.getbyte(at).inspect})"
    end
  end

  module_function

  # Lines naming where two snapshots differ, module by module. `sites`
  # labels the BADLINE module's values.
  def differences(first, second, sites)
    ours = Badline::Snapshot::Container.parse(first)
    theirs = Badline::Snapshot::Container.parse(second)
    names = (ours.sections.map(&:name) | theirs.sections.map(&:name))
    names.flat_map { |name| module_difference(name, ours[name], theirs[name], sites) }
  end

  def module_difference(name, ours, theirs, sites)
    return ["#{name}: only in the #{ours ? 'first' : 'second'}"] unless ours && theirs
    return ["#{name}: version #{ours.version} against #{theirs.version}"] unless ours.version == theirs.version
    return [] if ours.data == theirs.data

    if name == Badline::Snapshot::MachineState::NAME
      lines = StateDiff.lines(Badline::Snapshot::MachineState.state(ours),
                              Badline::Snapshot::MachineState.state(theirs), sites)
      return lines.map { |line| "#{name}: #{line}" }
    end
    ["#{name}: #{StateDiff.string_difference(ours.data, theirs.data)}"]
  end
end
