# PLAN.md

Tasks are tracked inline in this file.
Each story names at least one test (`bundle exec rake test`).

## Now

Decks moved to the sibling repo `~/workspace/slide-decks` as JSON (Story 17 done).
Story 18 (slide editor) is done: `public/index.html`, published to GitHub Pages from `public/`.
Release direction (proposal, not authoritative): `docs/releases-brainstorm.md`; its decisions log records what is settled.
The first git commits (here and in slide-decks) are Ryan's to make.

## Decisions

- 2026-09-28: Two repos. `slides` = engine + templates + brands + site; `slide-decks` = deck data + assets + index.json.
- 2026-09-28: Decks are JSON (browser-native). The engine still reads .yml, since JSON is valid YAML.

## Content split and editor

- [x] Story 17: Decks repo — decks live in `~/workspace/slide-decks/decks/<name>.json` with `assets/` and a generated `index.json`; the engine finds it as a sibling or via `$SLIDES_DECKS_DIR`, resolves deck names (`rake "slides:generate[govcenter]"`), and resolves asset paths from that repo.
  Verified: all 14 decks load to identical slides and config from YAML and JSON; image-deck renders match the pre-move renders (1 title slide differs by dither ≤1/255).
  Test: `test/decks_test.rb`.
- [x] Story 17a: Removed the stale `slides/decks/` (old YAML) and `slides/public/images/` (now `slide-decks/assets/`). Ryan ran the delete; tests pass without them.
- [x] Story 18: Slide editor — a single static page that manages deck JSON with basic UI (slide list, add/reorder/delete, template picker, field forms from `catalog.yml`) and an active Markdown drawer for the selected slide's body fields, with live preview.
  Files: the File System Access API (`showDirectoryPicker`, `createWritable`; Chromium) opens `~/workspace/slide-decks` and writes `decks/*.json` back to disk, so the browser, the IDE, Claude Code sessions, and git all see one file. Fallback (Safari/Firefox): download, or GitHub's `/edit` URL.
  Preview must use the real `templates/styles.css` + brand tokens, not a copy (retires the viewer's inline `SLIDE_CSS`).
  Built: `public/index.html` + `public/js/editor.js`, rendering with `public/js/engine-core.js` (browser mirror of the ERB templates and markdown) and `public/js/engine-data.js` (`rake slides:site`: styles, catalog, brands). Old viewer kept as `public/viewer.html`.
  Test: `test/editor_test.rb` (fake directory handle writes a real temp folder: byte-identical round trip, drawer edit saved, overflow warning, add/move/delete, asset image loads); `test/site_test.rb` (engine-data current; browser engine renders the same pixels as Ruby for every template × brand, tables, and legacy decks).

## Brand system
## Brand system

- [x] Story 11: Version control — `git init`, `.gitignore` covers generated output and local state.
  Test: `git status` lists only source files (no `public/slides/`, `.DS_Store`, `.ruby-lsp/`).
- [x] Story 12: Brand files — `brands/<name>/brand.yml` holds theme tokens, fonts, logo, and mark text.
  A deck says `brand: <name>` and overrides only what differs.
  Precedence: `styles.css` defaults < brand theme < deck theme.
  Unknown brands and unknown theme tokens fail loudly.
  Hardcoded template values (title gradient end, on-primary text, code background, caption) become tokens with unchanged defaults.
  Decks with duplicated themes migrate to brand references (two decks → slate; one → qart); all 210 slides verified byte-identical, except gradient dither of at most 2/255.
  Test: `test/brand_test.rb`.
- [x] Story 13: Brand sheet — `rake slides:sheet[brand]` renders swatches, type specimen, and every template in one brand to `public/sheets/<brand>.png`.
  Test: `test/brand_sheet_test.rb`.
- [x] Story 14: Overflow lint — `rake slides:lint[deck]` measures each rendered text element in Chrome and reports text that spills past the padded content box; exits 1 on overflow. `slides:generate` prints the same warnings.
  Test: `test/render_test.rb` (short slide passes, 20-bullet slide flagged).
- [ ] Story 15: Speaker notes — `notes:` per slide, exported beside the PDF, never rendered on the slide.
- [x] Story 15a: Render reliability — `lib/render.cjs` renders a whole deck in one Chrome, retries a slide once, and `lib/renderer.rb` confirms every artifact exists.
  Fixed a silent failure: Grover loaded pages as `http://example.com`, so relative image paths never resolved (9 image slides rendered empty boxes). Assets now resolve from the repo root, and missing files or failed remote images fail the render.
  Verified: all 210 slides old-vs-new rendered back-to-back; only the 9 image slides changed (now showing images), plus dither ≤1/255. One deck pointed at the defunct via.placeholder.com; switched to placehold.co.
  Test: `test/render_test.rb` (missing image fails loudly; PNG + PDF from one batch).
  Note: Chrome's text layout can drift by 1px between sessions, so compare old code vs new code rendered back-to-back, not against an old baseline.
- [ ] Story 16: Google Slides publish (optional) — one-way upload, one full-bleed image per slide, notes in speaker notes.

## Completed — Features

- [x] Story 1: CSS variable cleanup — convert hardcoded px to CSS variables
- [x] Story 2: Social format constants and scaling — SOCIAL_FORMATS, scale_factor_for, scaled_theme_for
- [x] Story 3: Social format generation in pipeline — social_formats in deck YAML, slides:social rake task
- [x] Story 4: Social formats in catalog — catalog.yml social_formats section, prompt_context update
- [x] Story 5: Image generator module — lib/image_generator.rb (OpenAI gpt-image-1)
- [x] Story 6: image_prompt field and resolution — image_prompt on full_image/content_image, .resolved.yml
- [x] Story 7: Image generation rake tasks — slides:generate_image, slides:generate_images
- [x] Story 8: content_image template — left text, right image layout
- [x] Story 9: Portfolio deck generator (moved to `slide-decks/tools/portfolio_generator.rb`; it is content tooling, not engine)
- [x] Story 10: PLAN.md and docs

## Engine additions made for decks

- [x] Pipe tables in `markdown()` (test: `test/markdown_test.rb`) and the `title_background`, `heading_font_style`, `table_*` tokens, added for the GovCenter deck; defaults verified byte-identical on 82 slides.

Deck history, deck to-dos, and deck handoffs live in `~/workspace/slide-decks` (PLAN.md and `.claude/inbox/done/`).

## Pending

- [ ] Retire `public/viewer.html` (old viewer: stale CSS copy, 5 of 6 templates, reads the gitignored `manifest.json`). The editor at `public/index.html` replaces it.
- [ ] Parity test speed: `test/site_test.rb` renders ~40 slides twice (~90 s). Render pages concurrently in `lib/render.cjs`, or trim the fixture set.
