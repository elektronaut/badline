# frozen_string_literal: true

# Values that take a machine millions of cycles to reach, worked out once
# for every spec that asks for them under the same key. Specs only read
# them: a machine State goes into a new machine, never back out.
module TakenOnce
  def self.fetch(key) = (@values ||= {})[key] ||= yield
end
