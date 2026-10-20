# frozen_string_literal: true

module Badline
  module Frontend
    # The pause menu's list of the true drives a PET or a CBM-II takes on
    # device 8, which the DRIVE 8 page's DRIVE TYPE row brings up: a row
    # for each model, the disks it reads at its right, and the one on the
    # bus said so. Up and Down move along the list, Return or a click picks
    # a model, and Left or Esc goes back to the page.
    class DriveTypes
      MODELS = %w[2031 2040 3040 4040 1001 8050 8250 9060 9090].freeze
      ACTIONS = %i[type2031 type2040 type3040 type4040 type1001 type8050 type8250 type9060 type9090].freeze

      def initialize(painter, buttons)
        @painter = painter
        @buttons = buttons
        @open = false
        @model = ""
      end

      def open? = @open

      # Opens the list with the focus on `model`, the drive on the bus, or
      # on the first if there's none.
      def open(model)
        @model = model
        @open = true
        index = MODELS.index(model)
        @buttons.focus = ACTIONS[index.nil? ? 0 : index]
      end

      def close
        @open = false
      end

      # The model `action` picks, or nil.
      def model_for(action)
        index = ACTIONS.index(action)
        index.nil? ? nil : MODELS[index]
      end

      # Draws the list `width` wide.
      def draw(left, top, width)
        @painter.text(left, top, "DRIVE 8 TYPE", MenuTheme::BRIGHT)
        top += 20
        MODELS.each_with_index do |model, index|
          media = Drives::IEEEModels::MEDIA.fetch(model).join(" ").upcase
          label = model == @model ? "#{model}, ON THE BUS" : model
          @buttons.row([left, top, width], label, ACTIONS[index], media)
          top += Buttons::HEIGHT + 2
        end
        @painter.text(left, top + 6, "RETURN: PICK  LEFT, ESC: BACK", MenuTheme::DIM)
      end
    end
  end
end
