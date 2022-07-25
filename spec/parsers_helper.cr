require "db"
require "json"
require "kemal"

require "protodec/utils"

require "spectator"

require "../src/invidious/helpers/macros"
require "../src/invidious/helpers/logger"
require "../src/invidious/helpers/utils"

require "../src/invidious/videos"
require "../src/invidious/comments"

require "../src/invidious/helpers/serialized_yt_data"
require "../src/invidious/yt_backend/extractors"
require "../src/invidious/yt_backend/extractors_utils"

OUTPUT = File.open(File::NULL, "w")
LOGGER = Invidious::LogHandler.new(OUTPUT, LogLevel::Off)

def load_mock(file) : Hash(String, JSON::Any)
  file = File.join(__DIR__, "..", "mocks", file + ".json")
  content = File.read(file)

  return JSON.parse(content).as_h
end

Spectator.configure do |config|
  config.fail_blank
  config.randomize
end
