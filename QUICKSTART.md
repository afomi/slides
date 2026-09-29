# Quick Start Guide

## 1. Inspect the Supported Templates

Before authoring a deck, inspect what the renderer can actually support:

```bash
bundle exec rake slides:catalog
bundle exec rake slides:prompt_context
```

This is the intended starting point for an LLM skill or conversational authoring flow.

## 2. Start from the Content-First Example

Open:

```text
../slide-decks/decks/content_first_example.json
```

This format separates:

- `content`
- `template`
- `theme`
- `output formats`

## 3. Generate the Deck

```bash
bundle exec rake "slides:generate[content_first_example]"
```

Output goes to:

```text
public/slides/content_first_example/
```

If the deck requests both formats, you will get:

- `slide_01.png`, `slide_02.png`, ...
- `content_first_example.pdf`

## 4. Customize Theme Without Touching Templates

Edit the deck-level `theme` block:

```yaml
theme:
  primary_color: "#0f766e"
  background_color: "#f8fafc"
  text_color: "#0f172a"
  padding: "88px"
```

Then regenerate.

## 5. Legacy Decks Still Work

Existing decks using slide-level `type` continue to render:

```bash
bundle exec rake "slides:generate[example]"
```

## Recommended Authoring Flow

1. Start with the message, not the layout.
2. Pick a supported template from `templates/catalog.yml`.
3. Keep content within the template’s intended regions and limits.
4. Export to PDF for deck use and PNG when image files are needed.
