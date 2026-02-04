# frozen_string_literal: true

module Rbrun
  class ResourcesController < ApplicationController
    def index
      inspector = ResourceInspector.new
      @resources = inspector.all
    end
  end
end
