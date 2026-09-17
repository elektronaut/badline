# frozen_string_literal: true

# Shims for core methods the Spinel AOT compiler's runtime does not carry.
# Under CRuby the guard is false and nothing here is defined, so the built-in
# implementations stand.
if RUBY_ENGINE == "spinel"
  # rubocop:disable-next Style/BitwisePredicate -- these are the methods in question
  class Integer
    def anybits?(mask) = (self & mask) != 0

    def nobits?(mask) = (self & mask).zero?

    def allbits?(mask) = (self & mask) == mask
  end
end
