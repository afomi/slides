require_relative 'test_helper'
require 'open3'
require 'tmpdir'
require_relative '../slide_generator'
require_relative '../lib/site_bundle'
require_relative '../lib/brand_sheet'

# The editor site renders slides in the browser with public/js/engine-core.js.
# These tests hold it to the Ruby engine: same slides, same pixels.
class SiteTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)

  def test_engine_data_is_current
    assert Slides::SiteBundle.current?, 'public/js/engine-data.js is stale: run `bundle exec rake slides:site`'
  end

  def js_render(decks)
    input = decks.map { |name, data| { name: name, data: data } }
    stdout, stderr, status = Open3.capture3('node', File.join(ROOT, 'test/support/js_render.cjs'), stdin_data: JSON.generate(input))
    assert status.success?, stderr
    JSON.parse(stdout)
  end

  # Every template in every brand (the brand-sheet samples), plus the fixture decks: tables, legacy format, assets.
  def parity_decks
    decks = Slides::SlideGenerator.brand_names.to_h do |brand|
      ["sheet-#{brand}", JSON.parse(JSON.generate(Slides::BrandSheet.new(brand).send(:sample_deck)))]
    end
    %w[tables legacy assets].each do |name|
      decks[name] = JSON.parse(File.read(Slides::SlideGenerator.resolve_deck(name)))
    end
    decks
  end

  def test_browser_engine_renders_the_same_pixels_as_ruby
    decks = parity_decks
    js = js_render(decks)

    Dir.mktmpdir do |dir|
      jobs = []
      pairs = []
      decks.each do |name, data|
        ruby = Slides::SlideGenerator.new("#{name}.json", data: data)
        ruby.rendered_slides.each_with_index do |(_slide, number, html), index|
          ruby_png = File.join(dir, "#{name}-#{number}-ruby.png")
          js_png = File.join(dir, "#{name}-#{number}-js.png")
          jobs << Slides::Renderer::Job.new(html: html, out: ruby_png, format: 'png', width: 1920, height: 1080)
          jobs << Slides::Renderer::Job.new(html: js.fetch(name).fetch(index), out: js_png, format: 'png', width: 1920, height: 1080)
          pairs << ["#{name} slide #{number}", ruby_png, js_png]
        end
      end

      Slides::Renderer.render(jobs, root: Slides::SlideGenerator.decks_dir)
      different = pairs.reject { |_label, a, b| File.binread(a) == File.binread(b) }.map(&:first)

      assert_empty different, "browser engine differs from Ruby on: #{different.join(', ')}"
      expected = Slides::SlideGenerator.brand_names.length * Slides::SlideGenerator.template_specs.length + 3 + 5 + 1
      assert_equal expected, pairs.length, 'parity set shrank: every template x brand plus the fixture decks'
    end
  end
end
