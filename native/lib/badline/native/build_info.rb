# frozen_string_literal: true

module Badline
  module Native
    # What built the binary. `rake native:build` writes its own copy of this
    # file ahead of this one on the load path, naming the badline revision
    # and the Spinel compiler. A build by hand gets these.
    REVISION = ""
    SPINEL = ""
  end
end
