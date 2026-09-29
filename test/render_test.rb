require_relative 'test_helper'
require 'tmpdir'
require_relative '../slide_generator'

# Drives real Chrome through lib/render.cjs (a few seconds).
class RenderTest < Minitest::Test
  def generator(slides)
    Slides::SlideGenerator.new('render_test.yml', data: { brand: 'slate', slides: slides })
  end

  def test_short_slide_has_no_overflow
    overflows = generator([{ template: 'normal', content: { title: 'Short', body: "- One\n- Two" } }]).lint

    assert_empty overflows
  end

  def test_lint_reports_text_past_the_bottom_edge
    body = (1..20).map { |n| "- Bullet number #{n} is here to push past the bottom of the slide" }.join("\n")
    overflows = generator([{ template: 'normal', content: { title: 'Too long', body: body } }]).lint

    refute_empty overflows
    assert(overflows.all? { |o| o[:slide_number] == 1 && o[:template] == 'normal' })
    assert(overflows.any? { |o| o[:bottom].positive? && o[:text].start_with?('Bullet number') })
  end

  def test_missing_local_image_fails_loudly
    slides = [{ template: 'content_image', content: { title: 'Broken', body: '- x', image: 'public/images/does-not-exist.png' } }]

    error = assert_raises(Slides::Renderer::RenderError) do
      Dir.mktmpdir { |dir| Slides::SlideGenerator.new('t.yml', output_dir: dir, data: { slides: slides }).generate(formats: ['png']) }
    end
    assert_match(%r{missing file: public/images/does-not-exist\.png}, error.message)
  end

  def test_generate_writes_png_and_pdf_from_one_batch
    Dir.mktmpdir do |dir|
      deck = Slides::SlideGenerator.new('batch.yml', output_dir: dir, data: { slides: [
        { template: 'title', content: { title: 'One' } },
        { template: 'section', content: { heading: 'Two' } }
      ] })
      artifacts = deck.generate(formats: %w[png pdf])

      assert_equal %w[slide_01.png slide_02.png batch.pdf], artifacts.map { |path| File.basename(path) }
      artifacts.each { |path| assert File.size?(path), "#{path} missing or empty" }
      assert_equal "\x89PNG".b, File.binread(artifacts.first, 4)
      assert_equal '%PDF', File.binread(artifacts.last, 4)
    end
  end
end
