require 'erb'
require 'fileutils'
require_relative '../slide_generator'

module Slides
  # One page per brand: color swatches, type specimen, and every template rendered in that brand.
  # Used to refine a visual language in one place, by a person or by an LLM reading the PNG.
  class BrandSheet
    COLUMNS = 3
    TILE_WIDTH = 576 # 3 x 576 + 2 x 32 gap = 1792 = 1920 - 2 x 64 padding

    # Tokens that hold colors (swatch row). Everything else is typography or spacing.
    COLOR_TOKEN = /(_color|_background|_gradient_end|_muted)\z/

    attr_reader :brand_name, :output_dir

    def initialize(brand_name, output_dir: 'public/sheets')
      @brand_name = brand_name
      @output_dir = output_dir
    end

    def brand
      @brand ||= SlideGenerator.load_brand(brand_name)
    end

    # styles.css defaults with the brand's overrides applied.
    def tokens
      SlideGenerator.theme_defaults.merge(brand[:theme].transform_keys(&:to_sym)).transform_values(&:to_s)
    end

    def generator
      @generator ||= SlideGenerator.new("sheet-#{brand_name}.yml", data: sample_deck)
    end

    def html
      rendered = generator.rendered_slides
      styles = SlideGenerator::BindingContext.new({}, 0, generator.deck_config).styles

      <<~HTML
        <!DOCTYPE html>
        <html>
        <head>
          <meta
            charset="UTF-8"
          >
          <title>#{h(brand[:name])} brand sheet</title>
          <style>
        #{styles}
        #{sheet_styles}
          </style>
        </head>
        <body
          class="sheet"
        >
          <header>
            <h1>#{h(brand[:name])}</h1>
            <p>#{h(brand[:description])}</p>
            <p
              class="meta"
            >brands/#{h(brand_name)}/brand.yml</p>
          </header>
          <section
            class="swatches"
          >
        #{swatches_html}
          </section>
          <section
            class="specimen"
          >
        #{specimen_html}
          </section>
          <section
            class="tiles"
          >
        #{rendered.map { |slide, _number, slide_html| tile_html(slide[:type], slide_html) }.join("\n")}
          </section>
        </body>
        </html>
      HTML
    end

    # Writes <brand>.html and <brand>.png; returns both paths.
    def generate
      FileUtils.mkdir_p(output_dir)
      html_path = File.join(output_dir, "#{brand_name}.html")
      png_path = File.join(output_dir, "#{brand_name}.png")

      page = html
      File.write(html_path, page)
      Renderer.render([Renderer::Job.new(html: page, out: png_path, format: 'png', width: 1920, height: 1080, full_page: true)])

      [html_path, png_path]
    end

    private

    def sample_deck
      {
        brand: brand_name,
        slides: [
          { template: 'title', content: { title: brand[:name], subtitle: 'Brand sheet: every template in one visual language' } },
          { template: 'section', content: { heading: 'Section heading' } },
          {
            template: 'normal',
            content: {
              title: 'Normal: title and body',
              body: "- A first point in body text\n- **Strong** emphasis uses the primary color\n- *Secondary* voice for asides\n- Inline `code` in the mono face"
            }
          },
          {
            template: 'two_column',
            content: {
              title: 'Two column: comparison',
              left: "**Before**\n- Themes copied deck to deck\n- Colors only",
              right: "**After**\n- One brand file\n- Colors, type, logo, mark"
            }
          },
          {
            template: 'content_image',
            content: {
              title: 'Content and image',
              body: "- Text on the left\n- Image on the right\n- Placeholder in brand colors",
              image: placeholder_image
            }
          },
          { template: 'full_image', content: { image: placeholder_image, caption: 'Full image with caption bar' } }
        ]
      }
    end

    def placeholder_image
      t = tokens
      svg = <<~SVG
        <svg xmlns="http://www.w3.org/2000/svg" width="1600" height="900" viewBox="0 0 1600 900">
          <defs>
            <linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
              <stop offset="0" stop-color="#{t[:primary_color]}"/>
              <stop offset="1" stop-color="#{t[:accent_color]}"/>
            </linearGradient>
          </defs>
          <rect width="1600" height="900" fill="url(#g)"/>
          <circle cx="1150" cy="330" r="220" fill="#{t[:background_color]}" fill-opacity="0.18"/>
        </svg>
      SVG
      "data:image/svg+xml;base64,#{Base64.strict_encode64(svg)}"
    end

    def swatches_html
      tokens.select { |name, _| name.to_s.match?(COLOR_TOKEN) }.map do |name, value|
        <<~HTML
          <div
            class="swatch"
          >
            <div
              class="chip"
              style="background: #{h(value)}"
            ></div>
            <div
              class="name"
            >#{h(name)}</div>
            <div
              class="value"
            >#{h(value)}</div>
          </div>
        HTML
      end.join
    end

    def specimen_html
      t = tokens
      rows = [
        ['title', 'var(--heading-font-family)', t[:title_size], t[:title_weight]],
        ['heading', 'var(--heading-font-family)', t[:heading_size], t[:heading_weight]],
        ['subheading', 'var(--heading-font-family)', t[:subheading_size], t[:heading_weight]],
        ['body', 'var(--font-family)', t[:body_size], '400'],
        ['mono', 'var(--font-mono)', t[:code_size], '400']
      ]

      rows.map do |label, family, size, weight|
        <<~HTML
          <div
            class="specimen-row"
          >
            <div
              class="label"
            >#{label} · #{h(size)} · #{h(weight)}</div>
            <div
              class="sample"
              style="font-family: #{family}; font-size: #{h(size)}; font-weight: #{h(weight)}"
            >Public truth, made visible 0123</div>
          </div>
        HTML
      end.join
    end

    def tile_html(template_name, slide_html)
      <<~HTML
        <figure
          class="tile"
        >
          <div
            class="frame"
          >
            <iframe
              srcdoc="#{h(slide_html)}"
              width="1920"
              height="1080"
              scrolling="no"
            ></iframe>
          </div>
          <figcaption>#{h(template_name)}</figcaption>
        </figure>
      HTML
    end

    def sheet_styles
      scale = TILE_WIDTH / 1920.0

      <<~CSS
        body.sheet {
          width: 1920px;
          height: auto;
          overflow: visible;
          padding: 64px;
          background: #ffffff;
          color: #0f172a;
        }
        .sheet header h1 { font-family: var(--heading-font-family); font-size: 56px; font-weight: var(--heading-weight); color: var(--primary-color); }
        .sheet header p { font-size: 22px; color: #475569; margin-top: 8px; }
        .sheet header .meta { font-family: var(--font-mono); font-size: 16px; }
        .sheet section { margin-top: 48px; }
        .sheet .swatches { display: flex; flex-wrap: wrap; gap: 24px; }
        .sheet .swatch { width: 160px; font-size: 14px; }
        .sheet .swatch .chip { height: 72px; border-radius: 8px; border: 1px solid #e2e8f0; margin-bottom: 8px; }
        .sheet .swatch .name { font-weight: 600; }
        .sheet .swatch .value { font-family: var(--font-mono); color: #64748b; word-break: break-all; }
        .sheet .specimen-row { display: flex; align-items: baseline; gap: 32px; padding: 12px 0; border-bottom: 1px solid #e2e8f0; }
        .sheet .specimen-row .label { width: 280px; flex: none; font-family: var(--font-mono); font-size: 14px; color: #64748b; }
        .sheet .specimen-row .sample { color: var(--text-color); white-space: nowrap; overflow: hidden; }
        .sheet .tiles { display: grid; grid-template-columns: repeat(#{COLUMNS}, #{TILE_WIDTH}px); gap: 32px; }
        .sheet .tile { margin: 0; }
        .sheet .tile .frame { width: #{TILE_WIDTH}px; height: #{(TILE_WIDTH * 9 / 16.0).round}px; overflow: hidden; border: 1px solid #e2e8f0; }
        .sheet .tile iframe { border: 0; transform: scale(#{scale}); transform-origin: 0 0; }
        .sheet .tile figcaption { font-family: var(--font-mono); font-size: 16px; color: #64748b; margin-top: 8px; }
      CSS
    end

    def h(value)
      ERB::Util.html_escape(value.to_s)
    end
  end
end
