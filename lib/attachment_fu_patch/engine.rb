module AttachmentFuPatch
  class Engine < ::Rails::Engine
    initializer :loader do |config|
      require 'patch'
    end
  end
end
