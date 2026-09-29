require_relative 'test_helper'
require_relative '../slide_generator'

class BrandTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)

  def deck(extra = {})
    { slides: [{ template: 'title', content: { title: 'Hello' } }] }.merge(extra)
  end

  def generator(extra = {})
    Slides::SlideGenerator.new('test.yml', data: deck(extra))
  end

  def test_theme_defaults_come_from_styles_css
    defaults = Slides::SlideGenerator.theme_defaults

    assert_equal '#2563eb', defaults[:primary_color]
    assert_equal '#000000', defaults[:title_gradient_end]
    assert_equal '48px', defaults[:brand_logo_height]
  end

  def test_brand_theme_applies
    theme = generator(brand: 'slate').deck_config[:theme]

    assert_equal '#1e293b', theme[:primary_color]
    assert_equal '88px', theme[:padding]
  end

  def test_deck_theme_overrides_brand_token_by_token
    theme = generator(brand: 'slate', theme: { primary_color: '#ff0000' }).deck_config[:theme]

    assert_equal '#ff0000', theme[:primary_color]
    assert_equal '#0d9488', theme[:accent_color]
  end

  def test_brand_may_be_declared_under_deck
    theme = generator(deck: { brand: 'qart' }).deck_config[:theme]

    assert_equal '#FD4F00', theme[:primary_color]
  end

  def test_unknown_brand_fails_and_lists_available
    error = assert_raises(RuntimeError) { generator(brand: 'nope') }

    assert_match(/Unknown brand 'nope'/, error.message)
    assert_match(/civic-studio/, error.message)
  end

  def test_unknown_theme_token_fails
    error = assert_raises(RuntimeError) { generator(theme: { primary_colour: '#fff' }) }

    assert_match(/Unknown theme token\(s\) in deck 'test': primary_colour/, error.message)
  end

  def test_every_brand_file_loads
    names = Slides::SlideGenerator.brand_names

    assert_includes names, 'civic-studio'
    names.each { |name| assert Slides::SlideGenerator.load_brand(name)[:name] }
  end

  def test_brand_mark_inlines_logo_and_mark_text
    html = generator(brand: 'civic-studio').rendered_slides.first.last

    assert_includes html, 'class="brand-mark"'
    assert_includes html, 'src="data:image/png;base64,'
    assert_includes html, '<span>Civic Studio</span>'
    assert_includes html, '@import url("https://fonts.googleapis.com/'
  end

  def test_no_brand_means_no_mark_and_no_imports
    html = generator.rendered_slides.first.last

    refute_includes html, 'brand-mark"'
    refute_includes html, '@import'
  end

  def test_every_existing_deck_still_loads
    paths = Slides::SlideGenerator.deck_paths
    refute_empty paths

    paths.each do |path|
      Slides::SlideGenerator.new(path)
    rescue => e
      flunk "#{File.basename(path)}: #{e.message}"
    end
  end

  def test_prompt_context_lists_brands
    assert_match(/- civic-studio: /, Slides::SlideGenerator.prompt_context)
  end
end
