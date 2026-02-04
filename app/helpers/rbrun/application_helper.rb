# frozen_string_literal: true

module Rbrun
  module ApplicationHelper
    def sandbox_state_class(sandbox)
      case sandbox.state
      when "pending"
        "bg-gray-100 text-gray-800"
      when "provisioning"
        "bg-yellow-100 text-yellow-800"
      when "running"
        "bg-green-100 text-green-800"
      when "stopped"
        "bg-gray-100 text-gray-800"
      when "failed"
        "bg-red-100 text-red-800"
      else
        "bg-gray-100 text-gray-800"
      end
    end

    def rbrun_importmap_tags(entry_point = "rbrun/application")
      importmap = Rbrun.importmap
      tags = []

      # Importmap JSON
      tags << content_tag(:script, importmap.to_json(resolver: self).html_safe,
                          type: "importmap", data: { turbo_track: "reload" })

      # Modulepreload links
      importmap.preloaded_module_paths(resolver: self).each do |path|
        tags << tag.link(rel: "modulepreload", href: path)
      end

      # Entry point script
      tags << content_tag(:script, %(import "#{entry_point}").html_safe,
                          type: "module", data: { turbo_track: "reload" })

      safe_join(tags, "\n")
    end
  end
end
