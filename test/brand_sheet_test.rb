require_relative 'test_helper'
require_relative '../lib/brand_sheet'

class BrandSheetTest < Minitest::Test
  def sheet
    @sheet ||= Slides::BrandSheet.new('civic-studio')
  end

  def test_sheet_renders_every_template
    html = sheet.html

    Slides::SlideGenerator.template_specs.each_key do |name|
      assert_includes html, "<figcaption>#{name}</figcaption>"
    end
  end

  def test_sheet_shows_brand_colors_as_swatches
    html = sheet.html

    assert_includes html, '>primary_color<'
    assert_includes html, '>#04455b<'
    assert_includes html, '>#86ebe9<'
  end

  def test_sheet_placeholder_images_use_brand_colors
    svg = Base64.decode64(sheet.send(:placeholder_image).split(',', 2).last)

    assert_includes svg, '#04455b'
    assert_includes svg, '#86ebe9'
  end
end
