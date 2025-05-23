# clover_restaurant.gemspec
require_relative 'lib/clover_restaurant/version'

Gem::Specification.new do |spec|
  spec.name          = "clover_restaurant"
  spec.version       = CloverRestaurant::VERSION
  spec.authors       = ["Your Name"]
  spec.email         = ["your.email@example.com"]

  spec.summary       = "A Ruby gem for simulating a restaurant using the Clover API"
  spec.description   = "Creates and manages restaurant entities like menu items, categories, employees, and orders using the Clover API"
  spec.homepage      = "https://github.com/yourusername/clover_restaurant"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 2.7.0"

  spec.metadata["allowed_push_host"] = "TODO: Set to your gem server 'https://example.com'"

  spec.metadata["homepage_uri"] = spec.homepage

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.glob(%w[
    lib/**/*
    exe/*
    *.gemspec
    README.md
    LICENSE.txt
    CHANGELOG.md
  ])

  spec.bindir        = "exe"
  spec.executables   = ["clover-restaurant"]
  spec.require_paths = ["lib"]

  # Runtime dependencies with bounded versions
  spec.add_dependency "rest-client", "~> 2.1"
  spec.add_dependency "json", "~> 2.6"
  spec.add_dependency "terminal-table", "~> 3.0"
  spec.add_dependency "sqlite3", "~> 1.6"
  spec.add_dependency "vcr", "~> 6.1"
  spec.add_dependency "webmock", "~> 3.18"
  spec.add_dependency "dotenv", "~> 2.8"
  spec.add_dependency "activesupport", "~> 7.0"
  spec.add_dependency "colorize", "~> 0.8"
  spec.add_dependency "faker", "~> 3.0"
  spec.add_dependency "httparty", "~> 0.21"

  # Development dependencies
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "byebug", "~> 11.1"
  spec.add_development_dependency "pry", "~> 0.14"
  spec.add_development_dependency "rubocop", "~> 1.50"
end
