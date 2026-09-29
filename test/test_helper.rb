# Engine tests run against generic fixture decks, never a real slide-decks checkout.
ENV['SLIDES_DECKS_DIR'] = File.expand_path('fixtures/slide-decks', __dir__)

require 'minitest/autorun'
