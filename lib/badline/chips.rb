# frozen_string_literal: true

# The chips badline/core's machines share. The C128's own, the Z80 and the
# VDC, stay out of the core: badline/c128 requires them.
require "badline/chips/cpu"
require "badline/chips/cia"
require "badline/chips/via"
require "badline/chips/sid"
require "badline/chips/vic"
require "badline/chips/vic_i"
