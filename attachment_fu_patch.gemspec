$:.push File.expand_path("../lib", __FILE__)

# Maintain your gem's version:
require "attachment_fu_patch/version"

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = "attachment_fu_patch"
  s.version     = AttachmentFuPatch::VERSION
  s.authors     = ["Andres Montano"]
  s.email       = ["amontano@virginia.edu"]
  s.homepage    = "http://www.thlib.org"
  s.summary     = "A patch to the AttachmentFu engine."
  s.description = "Adds support for raw images to AttachmentFu engine."

  s.files = Dir["{app,config,db,lib}/**/*"] + ["MIT-LICENSE", "Rakefile", "README.rdoc"]
  s.test_files = Dir["test/**/*"]

  s.add_dependency 'rails', '~> 4.1.5'
  s.add_dependency 'rmagick'

  s.add_development_dependency "sqlite3"
end
