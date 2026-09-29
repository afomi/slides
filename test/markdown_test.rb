require_relative 'test_helper'
require_relative '../slide_generator'

class MarkdownTest < Minitest::Test
  def markdown(text)
    Slides::SlideGenerator::BindingContext.new({}, 1, {}).markdown(text)
  end

  def test_pipe_table_renders_header_and_rows
    html = markdown("| Option | Buyer |\n|---|---|\n| B2G | A4 |\n| API | A2 |")

    assert_includes html, '<th>Option</th>'
    assert_equal 2, html.scan('<tr>').length - 1
    assert_includes html, '<td>A4</td>'
    refute_includes html, '---'
  end

  def test_table_closes_before_following_paragraph
    html = markdown("| a | b |\n|---|---|\n| 1 | 2 |\n\nAfter the table.")

    assert_operator html.index('</table>'), :<, html.index('<p>After the table.</p>')
  end

  def test_bullets_unchanged
    assert_equal "<ul>\n  <li><strong>One</strong></li>\n  <li>Two</li>\n</ul>", markdown("- **One**\n- Two")
  end
end
