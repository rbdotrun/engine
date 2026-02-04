# frozen_string_literal: true

pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "rbrun/application"
pin "rbrun/controllers", to: "rbrun/controllers/index.js"
pin "rbrun/controllers/application", to: "rbrun/controllers/application.js"
pin_all_from Rbrun::Engine.root.join("app/javascript/rbrun/controllers"),
             under: "rbrun/controllers"
