require 'json'
require_relative '../slide_generator'

module Slides
  # index.json for the decks repo: what a static site or another tool needs to list decks
  # without parsing every deck. Built from deck data alone (no renders), and deterministic,
  # so it only changes when a deck does.
  module DeckIndex
    SCHEMA = 'slide-decks/index@1'.freeze

    def self.build(decks_dir: SlideGenerator.decks_dir)
      decks = SlideGenerator.deck_paths.map do |path|
        deck = SlideGenerator.new(path)
        raw = JSON.parse(JSON.generate(YAML.safe_load(File.read(path), permitted_classes: [Symbol])))
        brand = raw.is_a?(Hash) ? (raw['brand'] || raw.dig('deck', 'brand')) : nil

        {
          name: File.basename(path, '.*'),
          path: path.delete_prefix("#{decks_dir}/"),
          title: deck.deck_config[:title],
          brand: brand,
          slide_count: deck.slides.length,
          templates: deck.slides.map { |slide| slide[:type] }.uniq,
          assets: deck.slides.map { |slide| slide[:image] }.compact.reject { |image| image.match?(%r{\A(https?:|data:)}) }.uniq
        }
      end

      { schema: SCHEMA, decks: decks }
    end

    def self.write(decks_dir: SlideGenerator.decks_dir)
      path = File.join(decks_dir, 'index.json')
      File.write(path, JSON.pretty_generate(build(decks_dir: decks_dir)) + "\n")
      path
    end
  end
end
