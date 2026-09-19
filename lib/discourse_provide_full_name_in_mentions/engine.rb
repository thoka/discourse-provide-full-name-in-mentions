# frozen_string_literal: true

module DiscourseProvideFullNameInMentions
  class Engine < ::Rails::Engine
    engine_name PLUGIN_NAME
    isolate_namespace DiscourseProvideFullNameInMentions
    config.autoload_paths << File.join(config.root, "lib")
  end
end
