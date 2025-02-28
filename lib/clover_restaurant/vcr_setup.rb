require "vcr"
require "webmock"

VCR.configure do |config|
  config.cassette_library_dir = "tmp/vcr_cassettes" # Change to preferred location
  config.hook_into :webmock
  config.default_cassette_options = { record: :new_episodes }
end
