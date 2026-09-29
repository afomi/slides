require_relative 'test_helper'
require 'open3'
require 'tmpdir'
require 'base64'
require_relative '../slide_generator'

# Drives the editor (public/index.html) in Chrome against a temp slide-decks folder.
class EditorTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  DOT_PNG = Base64.decode64('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==')

  def fixture_deck
    {
      'version' => 2,
      'deck' => { 'title' => 'Fixture', 'output' => { 'formats' => ['png'] } },
      'brand' => 'slate',
      'slides' => [
        { 'template' => 'title', 'role' => 'cover', 'content' => { 'title' => 'Fixture ⚑ deck', 'subtitle' => 'Round trip' } },
        { 'template' => 'normal', 'notes' => 'Keep me', 'content' => { 'title' => 'Points', 'body' => "- One\n- Two" } },
        { 'template' => 'two_column', 'content' => { 'title' => 'Compare', 'left_body' => '- L', 'right_body' => '- R' } }
      ]
    }
  end

  def test_editor_edits_the_deck_on_disk
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, 'decks'))
      FileUtils.mkdir_p(File.join(dir, 'assets', 'fixture'))
      File.binwrite(File.join(dir, 'assets', 'fixture', 'dot.png'), DOT_PNG)
      File.write(File.join(dir, 'decks', 'fixture.json'), JSON.pretty_generate(fixture_deck) + "\n")

      stdout, stderr, status = Open3.capture3('node', File.join(ROOT, 'test/support/editor_e2e.cjs'), dir)
      assert status.success?, stderr
      report = JSON.parse(stdout)

      assert_empty report['errors']
      assert_equal ['fixture'], report['decks']
      assert_equal 3, report['slideCount']
      assert report['roundTripIdentical'], 'open + save changed the file'

      assert report['previewUpdated']
      assert_equal ['Body', 'Speaker notes', 'Deck JSON'], report['drawerTabs']
      edited = report['afterEdit']['slides'][1]
      assert_equal "- Edited in the drawer\n- **Second** point", edited['content']['body']
      assert_equal 'Keep me', edited['notes']
      assert_equal '- L', report['afterEdit']['slides'][2]['content']['left_body'], 'existing alias keys are preserved'

      assert_match(/Overflow: "Bullet/, report['overflowWarning'])

      templates = report['afterStructure']['slides'].map { |s| s['template'] }
      assert_equal %w[section normal two_column], templates

      assert report['assetLoaded'], 'asset image did not load from the folder'

      assert report['drawerHiddenAtStart'], 'drawer should start hidden'
      assert report['drawerVisibleWhenOpen']
      assert report['drawerHiddenAfterClose'], 'Close did not hide the drawer'

      assert_equal 'fixture.json', report['openDeckStatus']
      assert report['openDeckNewDeckDisabled'], 'New deck needs a folder'
      assert_equal 'Saved through Open deck', report['afterOpenDeck']['slides'][0]['content']['heading']
      assert_equal 4, report['afterOpenDeck']['slides'].length

      assert_equal ['fixture'], report['decksDirDecks']
      assert_match(/Use Open folder and pick slide-decks/, report['decksDirImageWarning'])

      # What the editor saved is a valid deck for the Ruby engine.
      deck = Slides::SlideGenerator.new(File.join(dir, 'decks', 'fixture.json'))
      assert_equal 4, deck.slides.length
    end
  end
end
