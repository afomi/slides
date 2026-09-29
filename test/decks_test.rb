require_relative 'test_helper'
require 'tmpdir'
require_relative '../slide_generator'
require_relative '../lib/deck_index'

class DecksTest < Minitest::Test
  def with_decks_dir(dir)
    previous = ENV['SLIDES_DECKS_DIR']
    ENV['SLIDES_DECKS_DIR'] = dir
    yield
  ensure
    ENV['SLIDES_DECKS_DIR'] = previous
  end

  def test_decks_repo_defaults_to_sibling_slide_decks
    assert_equal File.expand_path('../../slide-decks', __dir__), Slides::SlideGenerator.default_decks_dir
  end

  def test_env_var_points_at_the_decks_repo
    assert_equal File.expand_path('fixtures/slide-decks', __dir__), Slides::SlideGenerator.decks_dir
  end

  def test_missing_decks_repo_names_the_path
    with_decks_dir('/nonexistent/decks-repo') do
      error = assert_raises(RuntimeError) { Slides::SlideGenerator.decks_dir }

      assert_includes error.message, '/nonexistent/decks-repo/decks'
    end
  end

  def test_deck_resolves_by_name
    path = Slides::SlideGenerator.resolve_deck('tables')

    assert_equal File.join(Slides::SlideGenerator.decks_dir, 'decks', 'tables.json'), path
  end

  def test_unknown_deck_lists_available
    error = assert_raises(RuntimeError) { Slides::SlideGenerator.resolve_deck('nope') }

    assert_match(/Unknown deck 'nope'. Available: assets, legacy, tables/, error.message)
  end

  def test_json_and_yaml_decks_load_identically
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, 'decks'))
      data = { 'brand' => 'slate', 'slides' => [{ 'template' => 'normal', 'content' => { 'title' => 'T', 'body' => "- a\n- b" } }] }
      File.write(File.join(dir, 'decks', 'a.json'), JSON.generate(data))
      File.write(File.join(dir, 'decks', 'b.yml'), YAML.dump(data))

      a = Slides::SlideGenerator.new(File.join(dir, 'decks', 'a.json'))
      b = Slides::SlideGenerator.new(File.join(dir, 'decks', 'b.yml'))

      assert_equal a.slides, b.slides
      assert_equal a.deck_config[:theme], b.deck_config[:theme]
    end
  end

  def test_assets_resolve_from_the_decks_repo
    deck = Slides::SlideGenerator.new(Slides::SlideGenerator.resolve_deck('assets'))

    assert_equal Slides::SlideGenerator.decks_dir, deck.send(:asset_root)
    deck.slides.map { |s| s[:image] }.compact.each do |image|
      assert File.file?(File.join(deck.send(:asset_root), image)), "missing asset #{image}"
    end
  end

  def test_index_lists_every_deck_with_its_fields
    index = Slides::DeckIndex.build

    assert_equal 'slide-decks/index@1', index[:schema]
    assert_equal Slides::SlideGenerator.deck_paths.length, index[:decks].length
    tables = index[:decks].find { |d| d[:name] == 'tables' }
    assert_equal 'decks/tables.json', tables[:path]
    assert_equal 'govcenter', tables[:brand]
    assert_equal 3, tables[:slide_count]
    assert_equal ['assets/fixture/dot.png'], index[:decks].find { |d| d[:name] == 'assets' }[:assets]
  end
end
