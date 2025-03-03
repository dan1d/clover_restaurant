# clover_restaurant.gemspec
Gem::Specification.new do |spec|
  spec.name          = "clover_restaurant"
  spec.version       = "0.1.0"
  spec.authors       = ["Daniel Dominguez"]
  spec.email         = ["danielfromarg@gmail.com"]

  spec.summary       = "A Ruby gem for interacting with Clover API for restaurant operations"
  spec.description   = "Comprehensive interface for Clover API including orders, items, inventory, customers, payments, and more"
  spec.homepage      = "https://github.com/dan1d/clover_restaurant"
  spec.license       = "MIT"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.6.0")

  spec.files         = Dir.glob("{bin,lib}/**/*") + %w[README.md]
  spec.require_paths = ["lib"]

  spec.add_dependency "activesupport", "~> 7.0"
  spec.add_dependency "colorize", "~> 0.8"
  spec.add_dependency "faker", "~> 2.19"
  spec.add_dependency "httparty", "~> 0.18.1"
  spec.add_dependency "json", "~> 2.3"
  spec.add_dependency "terminal-table", "~> 3.0"
  spec.add_dependency "vcr"
  spec.add_dependency "webmock"

  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency("byebug")
  spec.add_development_dependency "dotenv", "~> 2.8"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.9"
end
