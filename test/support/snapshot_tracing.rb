# frozen_string_literal: true

require "zlib"

# Names where two snapshots differ, module by module, and in each BL-*
# module the keys whose records differ, for bin/snapshot_check. Lists a
# snapshot's records too, for --fields.
module SnapshotTracing
  LIMIT = 8
  TAGS = { 0x01 => "int", 0x02 => "bool", 0x03 => "bytes", 0x04 => "ints", 0x05 => "text" }.freeze

  # A module's records, in the order written: [key, type, value], with an
  # int, a bool, an Array of ints or a binary String as the value.
  module Records
    module_function

    def of(section)
      bytes = Zlib.inflate(section.data)
      records = []
      pos = 0
      while pos < bytes.bytesize
        key, pos = take(bytes, pos)
        tag = bytes.getbyte(pos)
        value, pos = take(bytes, pos + 1)
        records << [key, TAGS.fetch(tag, "tag #{tag}"), decode(tag, value)]
      end
      records
    end

    def take(bytes, pos)
      length, pos = ber(bytes, pos)
      [bytes.byteslice(pos, length), pos + length]
    end

    def ber(bytes, pos)
      value = 0
      loop do
        byte = bytes.getbyte(pos)
        pos += 1
        value = (value << 7) | (byte & 0x7f)
        return [value, pos] if byte < 0x80
      end
    end

    def decode(tag, value)
      case tag
      when 0x01 then Badline::Snapshot::Keyed.unzigzag(ber(value, 0).first)
      when 0x02 then value.getbyte(0) == 1
      when 0x04 then ints(value)
      else value
      end
    end

    def ints(value)
      count, pos = ber(value, 0)
      Array.new(count) do
        number, pos = ber(value, pos)
        Badline::Snapshot::Keyed.unzigzag(number)
      end
    end
  end

  module_function

  # Lines naming where two snapshots, as bytes, differ, module by module.
  def differences(first, second)
    ours = Badline::Snapshot::Container.parse(first)
    theirs = Badline::Snapshot::Container.parse(second)
    names = (ours.sections.map(&:name) | theirs.sections.map(&:name))
    names.flat_map { |name| module_difference(name, ours[name], theirs[name]) }
  end

  def module_difference(name, ours, theirs)
    return ["#{name}: only in the #{ours ? 'first' : 'second'}"] unless ours && theirs
    return ["#{name}: version #{ours.version} against #{theirs.version}"] unless ours.version == theirs.version
    return [] if ours.data == theirs.data
    return ["#{name}: #{bytes_difference(ours.data, theirs.data)}"] unless name.start_with?("BL-")

    record_differences(Records.of(ours), Records.of(theirs)).map { |line| "#{name}: #{line}" }
  end

  # The keys whose records differ, the first LIMIT of them.
  def record_differences(ours, theirs)
    ours = ours.to_h { |key, type, value| [key, [type, value]] }
    theirs = theirs.to_h { |key, type, value| [key, [type, value]] }
    lines = (ours.keys | theirs.keys).filter_map do |key|
      next if ours[key] == theirs[key]
      next "#{key}: only in the #{ours.key?(key) ? 'first' : 'second'}" unless ours.key?(key) && theirs.key?(key)

      "#{key}: #{value_difference(ours[key], theirs[key])}"
    end
    lines.first(LIMIT)
  end

  def value_difference((our_type, ours), (their_type, theirs))
    return "#{our_type} against #{their_type}" unless our_type == their_type
    return bytes_difference(ours, theirs) if ours.is_a?(String) && our_type == "bytes"
    return list_difference(ours, theirs) if ours.is_a?(Array)

    "#{ours.inspect[0, 40]} against #{theirs.inspect[0, 40]}"
  end

  def list_difference(ours, theirs)
    at = (0...[ours.length, theirs.length].max).find { |i| ours[i] != theirs[i] }
    "#{ours.length} values against #{theirs.length}, first difference at #{at} " \
      "(#{ours[at].inspect} against #{theirs[at].inspect})"
  end

  def bytes_difference(ours, theirs)
    at = (0...[ours.bytesize, theirs.bytesize].min).find { |i| ours.getbyte(i) != theirs.getbyte(i) }
    at ||= [ours.bytesize, theirs.bytesize].min
    "#{ours.bytesize} bytes against #{theirs.bytesize}, first difference at byte #{at} " \
      "(#{ours.getbyte(at).inspect} against #{theirs.getbyte(at).inspect})"
  end

  # Lines listing every module of a snapshot and its records, each value
  # cut short.
  def fields(bytes)
    container = Badline::Snapshot::Container.parse(bytes)
    container.sections.flat_map do |section|
      header = "#{section} (#{section.data.bytesize} bytes)"
      next [header] unless section.name.start_with?("BL-")

      [header, *Records.of(section).map { |key, type, value| "  #{key} #{type} #{brief(value)}" }]
    end
  end

  def brief(value)
    case value
    when String then value.bytesize > 16 ? "#{value.bytesize} bytes" : value.inspect
    when Array then value.length > 16 ? "#{value.length} values" : value.inspect
    else value.inspect
    end
  end
end
