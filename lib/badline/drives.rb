# frozen_string_literal: true

# The drives and the serial bus badline/core's machines share. The C128's
# 1571 stays out of the core: badline/c128 requires it.
require "badline/drives/datasette"
require "badline/drives/serial_bus"
require "badline/drives/ieee_bus"
require "badline/drives/model1541"
require "badline/drives/model1581"
