# frozen_string_literal: true

# Round trips a unit through a keyed snapshot module (Snapshot::Keyed) into
# a fresh one, for the specs that check a unit's keyed fields against its
# positional save_state, which restores exactly.
module KeyedOracle
  # Saves `unit`'s fields, loads them into `target`, and returns the
  # reader, whose report says what the load left out or changed.
  def keyed_round_trip(unit, target, *prefix)
    out = Badline::Snapshot::Keyed::Writer.new
    unit.save_fields(out, *prefix)
    input = Badline::Snapshot::Keyed::Reader.parse(out.section("BL-TEST"))
    target.load_fields(input, *prefix)
    target.restored! if target.respond_to?(:restored!)
    input
  end

  # What `unit`'s positional save_state writes.
  def positional(unit)
    out = Badline::Snapshot::StateWriter.new
    unit.save_state(out)
    out.state
  end

  # A shallow copy of `unit` with `fields` set, as a unit the keyed load
  # recomputes or leaves alone holds them.
  def with_fields(unit, fields)
    unit.dup.tap do |copy|
      fields.each { |name, value| copy.instance_variable_set(name, value) }
    end
  end
end
