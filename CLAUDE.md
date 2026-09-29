# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

A declarative slide engine: deck data (JSON, in the sibling repo `~/workspace/slide-decks`) + HTML/ERB templates and brands (this repo) → PNG/PDF via Chrome.

Canonical authoring language: HTML templates.
Canonical authoring model: content-first JSON decks in `slide-decks/decks/<name>.json` (the engine also reads .yml; JSON is valid YAML).
This repo holds the engine, templates, brands, tests, and the viewer; it holds no decks.
Supported exports: PNG, PDF, and social media images (Twitter, LinkedIn, OG, square).

## Commands

```bash
# Generate slides from a deck
bundle exec rake "slides:generate[content_first_example]"   # deck name, or a path

# Export slides at a social media format
bundle exec rake "slides:social[example,twitter]"

# Generate a single image via OpenAI
bundle exec rake "slides:generate_image[a watercolor city hall]"

# Generate all images from image_prompt fields in a deck
bundle exec rake "slides:generate_images[my_deck]"

# List available decks
bundle exec rake slides:list

# Brands: list, and render a brand sheet (swatches, type, every template) to public/sheets/<brand>.png
bundle exec rake slides:brands
bundle exec rake "slides:sheet[civic-studio]"

# Check for text that overflows its slide (exit 1 if any); generate also warns
bundle exec rake "slides:lint[my_deck]"

# Rewrite slide-decks/index.json (one entry per deck)
bundle exec rake slides:index

# Tests (render_test drives real Chrome, a few seconds)
bundle exec rake test

# Inspect template capabilities
bundle exec rake slides:catalog
bundle exec rake slides:prompt_context

# Install dependencies (if puppeteer issues)
npm install
```

## Architecture

**Core flow:** JSON deck (slide-decks) → template catalog + normalization → ERB templates → HTML → `lib/render.cjs` (one Chrome per deck) → PNG/PDF

- `slide_generator.rb` - Main generator class with deck normalization, prompt context, and export helpers
- `templates/catalog.yml` - Machine-readable template capability spec for prompts and validation
- `templates/*.html.erb` - Six slide types: title, section, normal, two_column, content_image, full_image
- `templates/styles.css` - CSS variables for theming (loaded inline via `<%= styles %>`); its `:root` block is the authoritative list of theme tokens
- `brands/<name>/brand.yml` - Named brands: theme tokens, fonts, logo, mark. Decks reference one with `brand: <name>`
- `lib/brand_sheet.rb` - Renders one brand across every template for visual review
- `lib/renderer.rb` + `lib/render.cjs` - Batch renderer: one Node/Chrome process per deck, retries a slide once, measures overflow, and verifies every artifact exists. Relative asset paths (`assets/x.png`) resolve from the deck's repo (slide-decks); a missing file or failed remote image fails the render
- Decks live in `~/workspace/slide-decks` (or `$SLIDES_DECKS_DIR`): `decks/*.json`, `assets/`, `index.json`. `SlideGenerator.resolve_deck` turns a name into a path; relative asset paths resolve from that repo
- `lib/deck_index.rb` - Builds slide-decks/index.json from deck data alone
- `lib/image_generator.rb` - OpenAI image generation module (gpt-image-1)

**Template binding:** Templates receive `slide` (normalized hash with :type, :title, :content, etc.), `slide_number`, and helper methods `styles`, `markdown(text)`, and `brand_mark`.

**Theme precedence:** `styles.css` defaults < brand `theme:` < deck `theme:`. Unknown brands or theme tokens raise.

## Brand Workflow

- New decks should pick a brand (`rake slides:brands`) rather than paste an inline `theme:` block.
- To change a visual language, edit `brands/<name>/brand.yml`, run `rake "slides:sheet[<name>]"`, and read the PNG to check the result.
- Never hardcode a color, font, or weight in `styles.css` rules; add a token to `:root` with the current value as its default, so existing renders stay byte-identical.
- After changing `styles.css` or a template, re-render affected decks and compare PNGs against the previous output.


**Output:** `public/slides/[deck-name]/slide_01.png`, `slide_02.png`, and optionally `[deck-name].pdf`.

**Social media output:** `slide_01_twitter.png`, `slide_01_og.png`, etc. alongside standard PNGs.

## Slide Types

Valid templates:
- `title` - uses :title, :subtitle
- `section` - uses :heading
- `normal` - uses :title, :content
- `two_column` - uses :title, :left, :right
- `content_image` - uses :title, :content, :image (left text, right image)
- `full_image` - uses :image, :title (as caption)

Preferred deck format uses `template:` plus a nested `content:` block.
Legacy `type:` decks are still supported.

## Social Media Formats

Add `social_formats` to a deck's output config to generate scaled images:
- `twitter` - 1200x630 (Twitter/X card)
- `linkedin` - 1200x627 (LinkedIn post)
- `og` - 1200x630 (Open Graph preview)
- `square` - 1080x1080 (Instagram / general)

All CSS variables scale proportionally based on width ratio.

## Image Generation

Slides with `image_prompt` fields can have images generated via OpenAI:
1. Author the deck with `image_prompt` instead of `image`
2. Run `rake slides:generate_images[my_deck]`
3. Generated images go to `slide-decks/assets/generated/` with a manifest.json
4. A `<deck>.resolved.json` copy of the deck is written with repo-relative image paths (`assets/generated/…`)
5. `rake slides:generate` automatically uses the resolved deck if present

Requires `OPENAI_API_KEY` in environment.

## Dependencies

Requires `grover` gem and Chrome/Chromium for HTML-to-image/PDF conversion.
