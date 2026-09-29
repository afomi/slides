# Slide Generator

A declarative slide system that converts deck data into PNG and PDF slide decks using HTML/ERB templates.
Decks live in the sibling repo [`slide-decks`](../slide-decks) as JSON; this repo is the engine, templates, and brands.

The intended workflow is content-first: write the message, then pick the lightest template that fits it.
This works well for LLM-assisted authoring — an agent reads this file, produces a JSON deck, and renders it.

Snippets below are written in YAML for readability; decks are stored as JSON with the same structure (JSON is valid YAML, and the engine reads both).

## Quick Start

```bash
# Inspect available templates and constraints
bundle exec rake slides:catalog
bundle exec rake slides:prompt_context

# Generate a deck
bundle exec rake "slides:generate[content_first_example]"

# List all decks
bundle exec rake slides:list
```

Output is written to `public/slides/<deck-name>/`.

## Deck Format

```yaml
version: 2

deck:
  title: My Presentation
  output:
    formats:
      - png
      - pdf
  canvas:
    width: 1920
    height: 1080

theme:
  primary_color: "#0f766e"
  secondary_color: "#475569"
  accent_color: "#0d9488"
  background_color: "#f8fafc"
  text_color: "#0f172a"
  padding: "88px"

slides:
  - template: title
    role: cover
    content:
      title: My Presentation
      subtitle: A short supporting line

  - template: normal
    role: explanation
    content:
      title: Key Points
      body: |
        - First point
        - Second point
        - Third point
```

- `template` selects the visual layout
- `content` holds the authored message
- `role` is a freeform label for your own reference (cover, explanation, transition, etc.)
- `theme` maps directly to CSS variables — override any or all
- `deck.output.formats` accepts `png`, `pdf`, or both

## Templates

### `title`
Centered cover slide. Use for opening, closing, or a single thesis statement.

```yaml
- template: title
  content:
    title: Civil Registry        # required, ~10 words max
    subtitle: Public truth, made visible  # optional, one sentence
```

### `section`
Large section divider. Use for chapter breaks and topic transitions.

```yaml
- template: section
  content:
    heading: The Problem         # required, short phrase not a sentence
```

### `normal`
Title plus one body column. Use for key points, explanations, or process slides.

```yaml
- template: normal
  content:
    title: What We Built         # required
    body: |                      # required, 3–6 bullets or under 80 words
      - Phoenix/Elixir web application
      - Blockchain-anchored verifiable credentials
      - Self-service record search and verification
```

### `two_column`
Title plus two equal columns. Use for comparisons, before/after, or paired lists.

```yaml
- template: two_column
  content:
    title: Two Perspectives      # required
    left: |                      # required, keep balanced with right
      **Option A**
      - Point one
      - Point two
    right: |                     # required
      **Option B**
      - Point one
      - Point two
```

### `content_image`
Title, left text column, right image. Use for project cards or feature highlights.

```yaml
- template: content_image
  content:
    title: Feature Highlight     # required
    body: |                      # required, 3–5 bullets
      - Key capability
      - Supporting detail
    image: assets/my_deck/photo.png  # required (or use image_prompt)
    image_prompt: "a watercolor city hall"  # optional, generates image via OpenAI
```

### `full_image`
Full-bleed image with optional caption. Use for visual punch slides or photographic interludes.

```yaml
- template: full_image
  content:
    image: assets/my_deck/photo.png  # required
    title: Optional caption text    # optional
```

## Brands

A brand is a named visual language shared across decks: theme tokens, web fonts, a logo, and mark text.
Brands live in `brands/<name>/brand.yml`, with assets (the logo) beside it.

```yaml
# slide-decks/decks/my_deck.json, shown as YAML
brand: civic-studio      # top-level, or under deck:
theme:
  accent_color: "#f59e0b" # optional: override single tokens for this deck only
```

Precedence: `templates/styles.css` defaults < brand `theme:` < deck `theme:`.
Unknown brands and unknown theme tokens raise an error that names the valid options.

```yaml
# brands/civic-studio/brand.yml
name: Civic Studio
description: One line an LLM can use to pick this brand.
fonts:                    # optional stylesheet URLs, loaded via @import
  - https://fonts.googleapis.com/css2?family=Public+Sans:wght@300;400;600&display=swap
logo: logo.png            # optional; relative to the brand directory; inlined as a data URI
mark: Civic Studio        # optional text beside the logo, bottom-left of every slide except full_image
theme:
  primary_color: "#04455b"
  font_family: "'Public Sans', sans-serif"
```

Refine a brand by editing its `brand.yml` and rendering its sheet:

```bash
bundle exec rake slides:brands              # list brands
bundle exec rake "slides:sheet[civic-studio]" # public/sheets/civic-studio.png (+ .html)
bundle exec rake slides:sheet               # every brand
```

The sheet shows color swatches, a type specimen, and all six templates in that brand on one page.

## Theme Tokens

Every theme key maps to a CSS variable declared in the `:root` block of `templates/styles.css` (`primary_color` → `--primary-color`).
That block is the authoritative list, and its values are the defaults.
The most-used tokens:

| Key | Controls |
|---|---|
| `primary_color` | Headings, bullets, strong text, title-slide gradient start, section rule |
| `secondary_color` | Emphasized (`*em*`) text |
| `accent_color` | Title rule (when `title_rule_*` are non-zero) |
| `background_color`, `text_color`, `text_light` | Ground, body text, slide number and mark |
| `on_primary_color`, `on_primary_muted` | Text on the title slide and caption bar |
| `title_gradient_end` | Title-slide gradient end |
| `code_background`, `caption_background` | Inline code chip, full-image caption bar |
| `font_family`, `heading_font_family`, `font_mono` | Typefaces |
| `title_weight`, `subtitle_weight`, `heading_weight` | Weights |
| `title_size`, `heading_size`, `subheading_size`, `body_size`, `small_size` | Type scale |
| `title_rule_width`, `title_rule_height`, `title_rule_gap` | Accent bar under the cover title (`0px` = off) |
| `padding`, `gap`, `list_gap`, `brand_logo_height` | Spacing |

## Social Media Formats

Add `social_formats` to the output config to generate scaled images alongside standard PNGs:

```yaml
deck:
  output:
    formats: [png]
    social_formats: [twitter, linkedin, og, square]
```

| Format | Size | Use |
|---|---|---|
| `twitter` | 1200×630 | Twitter/X card |
| `linkedin` | 1200×627 | LinkedIn post |
| `og` | 1200×630 | Open Graph preview |
| `square` | 1080×1080 | Instagram / general |

Output: `public/slides/<deck-name>/slide_01_twitter.png`, etc.

## Image Generation

Slides can have images generated via OpenAI instead of supplying a path:

1. Use `image_prompt` instead of `image` in a `content_image` or `full_image` slide
2. Run `bundle exec rake "slides:generate_images[my_deck]"`
3. Images are saved to `slide-decks/assets/generated/` and a `<deck>.resolved.json` copy of the deck is written
4. `slides:generate` automatically uses the resolved deck if present

```bash
# Generate a single image
bundle exec rake "slides:generate_image[a watercolor city hall]"

# Generate all images in a deck
bundle exec rake "slides:generate_images[my_deck]"
```

Requires `OPENAI_API_KEY` in the environment.

## Authoring Rules

- Author the message first, then choose the lightest template that fits it.
- Keep content inside the supported fields; do not invent new regions.
- If a slide will overflow, split it into two slides or choose a denser template.
- Prefer PDF for deck distribution and PNG for image pipelines or thumbnails.
- `normal` body: aim for 3–6 bullets or under 80 words.
- `two_column`: keep both columns balanced in length.
- `title`: keep the title to roughly 10 words or fewer.
- `section`: use a short phrase, not a sentence.

## Checking Fit

`rake "slides:lint[my_deck]"` renders every slide and lists text that spills past the slide's padded content box, with the overflow in pixels.
It exits 1 when anything overflows, so an LLM or CI can loop until the deck fits.
`slides:generate` prints the same warnings after rendering.

Image paths in decks resolve from the decks repo root (`assets/my_deck/photo.png`).
A missing image or failed remote image stops the render with the path, rather than rendering an empty box.

## Dependencies

- Ruby (`grover` is only used by the standalone `slides:render` task)
- Chrome or Chromium (for Puppeteer/Grover rendering)
- Node.js / npm (for Puppeteer)

```bash
bundle install
npm install
```
