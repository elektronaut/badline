# frozen_string_literal: true

require "spec_helper"
require "badline/snapshot/field_doc"

describe Badline::Snapshot::FieldDoc do
  let(:loads) { described_class.loads }

  it "matches doc/snapshot-format.md, which rake snapshot:fields writes" do
    expect(described_class.markdown(loads)).to eq(File.read(described_class::PATH))
  end

  # Each module of each machine: the keys its records hold that the load
  # doesn't read. A load reads more keys than a save writes, since it asks
  # for every optional one, but it reads every key written.
  def unread(load)
    load.fields.flat_map do |name, fields|
      read = fields.map(&:key)
      load.written[name].keys.reject { |key| read.include?(key) }.map { |key| "#{load.family} #{name} #{key}" }
    end
  end

  it "reads every key each module writes" do
    expect(loads.flat_map { |load| unread(load) }).to be_empty
  end

  it "writes every module each machine reads" do
    missing = loads.flat_map do |load|
      load.fields.keys.reject { |name| load.written.fetch(name).any? }.map { |name| "#{load.family} #{name}" }
    end
    expect(missing).to be_empty
  end
end
