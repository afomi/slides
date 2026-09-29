require 'yaml'
require 'json'
require 'erb'
require 'fileutils'
require 'base64'
require_relative 'lib/renderer'

module Slides
  class SlideGenerator
    TEMPLATE_CATALOG_PATH = File.join(File.dirname(__FILE__), 'templates', 'catalog.yml')
    STYLES_PATH = File.join(File.dirname(__FILE__), 'templates', 'styles.css')
    BRANDS_DIR = File.join(File.dirname(__FILE__), 'brands')
    ENGINE_ROOT = File.dirname(File.expand_path(__FILE__))
    DECK_EXTENSIONS = %w[.json .yml].freeze
    DEFAULT_OUTPUT_FORMATS = %w[png].freeze
    SUPPORTED_OUTPUT_FORMATS = %w[png pdf].freeze
    DEFAULT_PAGE_HEIGHT_IN = 7.5

    SOCIAL_FORMATS = {
      'twitter'  => { width: 1200, height: 630 },
      'linkedin' => { width: 1200, height: 627 },
      'og'       => { width: 1200, height: 630 },
      'square'   => { width: 1080, height: 1080 }
    }.freeze

    # Default CSS variable values from styles.css (used as base for scaling)
    SCALABLE_THEME_DEFAULTS = {
      title_size: 96, subtitle_size: 48, heading_size: 72, subheading_size: 40,
      body_size: 32, small_size: 24, padding: 80, gap: 40, list_gap: 24,
      bullet_indent: 60, bullet_offset: 20, bullet_size: 48, border_width: 20,
      code_size: 28, code_padding_y: 4, code_padding_x: 12, code_radius: 4,
      slide_number_bottom: 40, slide_number_right: 60, brand_logo_height: 48, table_size: 26
    }.freeze

    attr_reader :deck_path, :output_dir, :slides, :deck_config

    def self.template_catalog
      @template_catalog ||= YAML.safe_load(
        File.read(TEMPLATE_CATALOG_PATH),
        permitted_classes: [Symbol],
        symbolize_names: true
      )
    end

    def self.template_specs
      template_catalog[:templates] || {}
    end

    # Theme tokens declared in the :root block of styles.css, as { primary_color: '#2563eb', ... }.
    # These are the only keys a brand or deck theme may set.
    def self.theme_defaults
      root = File.read(STYLES_PATH)[/:root\s*\{(.*?)\n\}/m, 1].to_s
      root.scan(/^\s*--([a-z0-9-]+):\s*([^;]+);/).to_h do |name, value|
        [name.tr('-', '_').to_sym, value.strip]
      end
    end

    # Content repo: ~/workspace/slide-decks by default (sibling of this engine), or $SLIDES_DECKS_DIR.
    def self.default_decks_dir
      File.expand_path(File.join(ENGINE_ROOT, '..', 'slide-decks'))
    end

    def self.decks_dir
      dir = File.expand_path(ENV['SLIDES_DECKS_DIR'] || default_decks_dir)
      unless File.directory?(File.join(dir, 'decks'))
        raise "Decks repo not found: #{dir}/decks. Clone slide-decks beside this repo or set SLIDES_DECKS_DIR."
      end

      dir
    end

    def self.deck_paths
      DECK_EXTENSIONS.flat_map { |ext| Dir.glob(File.join(decks_dir, 'decks', "*#{ext}")) }
                     .reject { |path| path.include?('.resolved.') }
                     .sort
    end

    # Accepts a deck name ("govcenter") or a path. Names resolve in the decks repo, .json before .yml.
    def self.resolve_deck(name_or_path)
      path = File.expand_path(name_or_path.to_s)
      return path if File.file?(path)

      name = File.basename(name_or_path.to_s).sub(/\.(json|ya?ml)\z/, '')
      found = DECK_EXTENSIONS.map { |ext| File.join(decks_dir, 'decks', "#{name}#{ext}") }.find { |p| File.file?(p) }
      return found if found

      raise "Unknown deck '#{name_or_path}'. Available: #{deck_paths.map { |p| File.basename(p, '.*') }.join(', ')}"
    end

    def self.describe_overflow(overflow)
      edges = []
      edges << "#{overflow[:bottom]}px past bottom" if overflow[:bottom].to_i.positive?
      edges << "#{overflow[:right]}px past right" if overflow[:right].to_i.positive?
      "#{overflow[:element]} \"#{overflow[:text]}\" — #{edges.join(', ')}"
    end

    def self.brand_names
      Dir.glob(File.join(BRANDS_DIR, '*', 'brand.yml')).map { |path| File.basename(File.dirname(path)) }.sort
    end

    # Loads brands/<name>/brand.yml. Asset paths (logo) resolve relative to the brand's directory.
    def self.load_brand(name)
      path = File.join(BRANDS_DIR, name.to_s, 'brand.yml')
      unless File.exist?(path)
        raise "Unknown brand '#{name}'. Available: #{brand_names.join(', ')}"
      end

      data = YAML.safe_load(File.read(path), symbolize_names: true) || {}
      theme = data[:theme] || {}
      validate_theme_keys!(theme, "brand '#{name}'")

      logo_path = data[:logo] && File.join(File.dirname(path), data[:logo])
      if logo_path && !File.exist?(logo_path)
        raise "Brand '#{name}' logo not found: #{logo_path}"
      end

      {
        key: name.to_s,
        name: data[:name] || name.to_s,
        description: data[:description],
        theme: theme,
        fonts: Array(data[:fonts]),
        logo_path: logo_path,
        mark: data[:mark]
      }
    end

    def self.validate_theme_keys!(theme, source)
      unknown = theme.keys.map(&:to_sym) - theme_defaults.keys
      return if unknown.empty?

      raise "Unknown theme token(s) in #{source}: #{unknown.join(', ')}. " \
            "Known tokens are the variables in templates/styles.css :root."
    end

    def self.prompt_context
      catalog = template_catalog
      canvas = catalog[:canvas] || {}
      authoring = catalog[:authoring] || {}

      lines = []
      lines << "Canonical template language: #{authoring[:canonical_template_language] || 'html'}."
      lines << "Supported export formats: #{Array(authoring[:export_formats]).join(', ')}."
      lines << "Default canvas: #{canvas[:width]}x#{canvas[:height]} (#{canvas[:aspect_ratio]})."

      Array(authoring[:prompt_rules]).each do |rule|
        lines << "Rule: #{rule}"
      end

      lines << ""
      lines << "Supported templates:"

      template_specs.each do |template_name, spec|
        required = Array(spec[:required_fields]).join(', ')
        optional = Array(spec[:optional_fields]).join(', ')
        best_for = Array(spec[:best_for]).join(', ')

        lines << "- #{template_name}: #{spec[:description]}"
        lines << "  Best for: #{best_for}" unless best_for.empty?
        lines << "  Required fields: #{required}" unless required.empty?
        lines << "  Optional fields: #{optional}" unless optional.empty?

        Array(spec[:constraints]).each do |constraint|
          lines << "  Constraint: #{constraint}"
        end

        Array(spec[:regions]).each do |region_name, region_spec|
          bounds = [region_spec[:x], region_spec[:y], region_spec[:width], region_spec[:height]]
          lines << "  Region #{region_name}: #{region_spec[:description]} (#{bounds.join(', ')})"
        end
      end

      unless brand_names.empty?
        lines << ""
        lines << "Brands (set `brand: <name>` at the top of a deck; a deck `theme:` overrides individual tokens):"
        brand_names.each do |name|
          brand = load_brand(name)
          lines << "- #{name}: #{brand[:description] || brand[:name]}"
        end
      end

      social = catalog[:social_formats] || {}
      unless social.empty?
        lines << ""
        lines << "Social media export formats (add to output.social_formats):"
        social.each do |name, spec|
          lines << "- #{name}: #{spec[:width]}x#{spec[:height]} — #{spec[:description]}"
        end
      end

      lines.join("\n")
    end

    # data: an already-parsed deck hash (string or symbol keys); deck_path then only names the deck.
    def initialize(deck_path, output_dir: 'public/slides', data: nil)
      @deck_path = deck_path
      @output_dir = output_dir
      @slides = []
      @deck_config = {}
      load_deck(data)
    end

    # [[slide, slide_number, html], ...] at the deck's own canvas size.
    def rendered_slides
      slides.each_with_index.map do |slide, index|
        slide_number = index + 1
        [slide, slide_number, render_slide(slide, slide_number)]
      end
    end

    def generate(formats: nil)
      FileUtils.mkdir_p(output_dir)

      requested_formats = normalize_output_formats(formats || deck_config[:output_formats])
      rendered = rendered_slides
      jobs = []

      if requested_formats.include?('png')
        rendered.each do |_slide, slide_number, html|
          jobs << slide_job(html, File.join(output_dir, "slide_#{pad(slide_number)}.png"), measure: true)
        end
      end

      if requested_formats.include?('pdf')
        jobs << slide_job(build_pdf_document(rendered.map(&:last)), File.join(output_dir, "#{deck_name}.pdf"), format: 'pdf')
      end

      (deck_config[:social_formats] || []).each do |format_name|
        jobs.concat(social_jobs(format_name))
      end

      puts "Rendering #{jobs.length} artifact(s) for #{slides.length} slide(s) in one browser..."
      results = Renderer.render(jobs, root: asset_root)
      report_overflows(overflows_from(results, jobs))

      artifacts = jobs.map(&:out)
      puts "\n✓ Generated #{artifacts.length} artifact(s) in #{output_dir}"
      artifacts.each { |artifact| puts "  - #{artifact}" }
      artifacts
    end

    # Renders every slide (without writing images) and returns text that spills past the padded
    # content box: [{ slide_number:, template:, element:, text:, bottom:, right: }] (px overflow).
    def lint
      jobs = rendered_slides.map { |_slide, _number, html| slide_job(html, nil, format: 'none', measure: true) }
      overflows_from(Renderer.render(jobs, root: asset_root), jobs)
    end

    def has_unresolved_image_prompts?
      slides.any? { |s| !blank?(s[:image_prompt]) && blank?(s[:image]) }
    end

    # Generates images for image_prompt fields into <decks repo>/assets/generated and writes
    # <deck>.resolved.<ext> with repo-relative image paths.
    def resolve_image_prompts!(output_dir: nil)
      require_relative 'lib/image_generator'

      img_dir = output_dir || File.join(asset_root, 'assets', 'generated')
      resolved_any = false

      slides.each do |slide|
        next if blank?(slide[:image_prompt]) || !blank?(slide[:image])

        result = Slides::ImageGenerator.generate(slide[:image_prompt], output_dir: img_dir)
        if result
          image = relative_to_asset_root(result[:file])
          slide[:image] = image
          slide[:content_payload][:image] = image if slide[:content_payload]
          resolved_any = true
        end
      end

      if resolved_any
        write_resolved_deck
      end

      resolved_any
    end

    def generate_social(format_name)
      FileUtils.mkdir_p(output_dir)
      jobs = social_jobs(format_name)
      Renderer.render(jobs, root: asset_root)
      jobs.map(&:out)
    end

    private

    def load_deck(data = nil)
      data = data ? symbolize_hash_or_array(data) : YAML.safe_load(File.read(deck_path), permitted_classes: [Symbol], symbolize_names: true)

      slide_data =
        if data.is_a?(Array)
          data
        else
          data[:slides]
        end

      unless slide_data.is_a?(Array)
        raise "Deck must be an array of slides or a hash with a top-level 'slides' key"
      end

      @deck_config = normalize_deck_config(data)
      @slides = slide_data.map { |slide| normalize_slide(slide) }
    end

    def normalize_deck_config(data)
      return default_deck_config if data.is_a?(Array)

      deck = fetch_hash(data, :deck)
      output = fetch_hash(deck, :output).merge(fetch_hash(data, :output))
      canvas = fetch_hash(deck, :canvas).merge(fetch_hash(data, :canvas))
      deck_theme = fetch_hash(deck, :theme).merge(fetch_hash(data, :theme))
      self.class.validate_theme_keys!(deck_theme, "deck '#{deck_name}'")

      brand_name = data[:brand] || deck[:brand]
      brand = brand_name ? self.class.load_brand(brand_name) : nil
      theme = (brand ? brand[:theme] : {}).merge(deck_theme)

      slide_width = canvas[:width] || self.class.template_catalog.dig(:canvas, :width)
      slide_height = canvas[:height] || self.class.template_catalog.dig(:canvas, :height)

      theme[:slide_width] = "#{slide_width}px" if slide_width
      theme[:slide_height] = "#{slide_height}px" if slide_height

      {
        title: deck[:title] || deck_name,
        theme: theme,
        canvas: {
          width: slide_width,
          height: slide_height
        },
        output_formats: normalize_output_formats(output[:formats] || output[:format]),
        social_formats: normalize_social_formats(output[:social_formats]),
        notes: deck[:notes],
        brand: brand
      }
    end

    def default_deck_config
      canvas = self.class.template_catalog[:canvas] || {}

      {
        title: deck_name,
        theme: {
          slide_width: "#{canvas[:width]}px",
          slide_height: "#{canvas[:height]}px"
        },
        canvas: {
          width: canvas[:width],
          height: canvas[:height]
        },
        output_formats: DEFAULT_OUTPUT_FORMATS,
        social_formats: [],
        notes: nil
      }
    end

    def normalize_slide(slide)
      slide = symbolize_hash(slide)
      template_name = (slide[:template] || slide[:type]).to_s

      if template_name.empty?
        raise "Missing 'template' or legacy 'type' attribute in slide: #{slide.inspect}"
      end

      spec = template_spec(template_name)
      content = normalize_content_payload(slide, spec)

      normalized = {
        type: template_name,
        title: content[:title],
        subtitle: content[:subtitle],
        heading: content[:heading],
        content: content[:content],
        left: content[:left],
        right: content[:right],
        image: content[:image],
        image_prompt: content[:image_prompt],
        background: content[:background],
        notes: slide[:notes],
        role: slide[:role],
        prompt: slide[:prompt],
        content_payload: content
      }

      validate_required_fields!(normalized, spec)
      normalized
    end

    def normalize_content_payload(slide, spec)
      raw_content =
        case slide[:content]
        when Hash
          symbolize_hash(slide[:content])
        else
          {}
        end

      field_aliases = fetch_hash(spec, :field_aliases)

      payload =
        field_aliases.each_with_object({}) do |(render_key, aliases), acc|
          value = value_for_aliases(Array(aliases), slide, raw_content)
          acc[render_key] = value unless blank?(value)
        end

      # Preserve legacy top-level fields that are not called through content maps.
      payload[:notes] = slide[:notes] if slide.key?(:notes)
      payload
    end

    def validate_required_fields!(slide, spec)
      missing = Array(spec[:required_fields]).select do |field_name|
        # image_prompt satisfies the image requirement
        if field_name.to_s == 'image' && !blank?(slide[:image_prompt])
          false
        else
          blank?(slide[field_name.to_sym])
        end
      end

      return if missing.empty?

      raise "Slide '#{slide[:type]}' is missing required field(s): #{missing.join(', ')}"
    end

    def render_slide(slide, slide_number)
      template_name = slide[:type]
      template_path = File.join(File.dirname(__FILE__), 'templates', "#{template_name}.html.erb")

      unless File.exist?(template_path)
        raise "Template not found: #{template_path}"
      end

      template = File.read(template_path)
      erb = ERB.new(template)

      binding_context = BindingContext.new(slide, slide_number, deck_config)
      erb.result(binding_context.get_binding)
    end

    def slide_job(html, out, format: 'png', measure: false, width: canvas_width, height: canvas_height)
      Renderer::Job.new(html: html, out: out, format: format, width: width, height: height, measure: measure)
    end

    def social_jobs(format_name)
      fmt = SOCIAL_FORMATS[format_name]
      raise "Unknown social format: #{format_name}. Valid: #{SOCIAL_FORMATS.keys.join(', ')}" unless fmt

      scaled_config = deck_config.merge(theme: scaled_theme_for(format_name))
      slides.each_with_index.map do |slide, index|
        slide_number = index + 1
        html = render_slide_with_config(slide, slide_number, scaled_config)
        out = File.join(output_dir, "slide_#{pad(slide_number)}_#{format_name}.png")
        slide_job(html, out, width: fmt[:width], height: fmt[:height])
      end
    end

    # Measured jobs are one per slide, in slide order, at the start of the job list.
    def overflows_from(results, jobs)
      results.each_with_index.flat_map do |result, index|
        next [] unless jobs[index].measure

        slide = slides[index]
        Array(result['overflows']).map do |overflow|
          { slide_number: index + 1, template: slide[:type] }.merge(overflow.transform_keys(&:to_sym))
        end
      end
    end

    def report_overflows(overflows)
      return if overflows.empty?

      puts "\n⚠ #{overflows.length} element(s) overflow the slide's content box (run rake slides:lint for detail):"
      overflows.each { |o| puts "  slide #{o[:slide_number]} (#{o[:template]}): #{Slides::SlideGenerator.describe_overflow(o)}" }
    end

    def pad(number)
      number.to_s.rjust(2, '0')
    end

    def render_slide_with_config(slide, slide_number, config)
      template_name = slide[:type]
      template_path = File.join(File.dirname(__FILE__), 'templates', "#{template_name}.html.erb")

      unless File.exist?(template_path)
        raise "Template not found: #{template_path}"
      end

      template = File.read(template_path)
      erb = ERB.new(template)

      binding_context = BindingContext.new(slide, slide_number, config)
      erb.result(binding_context.get_binding)
    end

    def scale_factor_for(target_width)
      target_width.to_f / canvas_width.to_f
    end

    def scaled_theme_for(format_name)
      fmt = SOCIAL_FORMATS[format_name]
      raise "Unknown social format: #{format_name}" unless fmt

      scale = scale_factor_for(fmt[:width])
      base_theme = deck_config[:theme] || {}

      scaled = SCALABLE_THEME_DEFAULTS.each_with_object({}) do |(key, default_val), acc|
        current = base_theme[key]
        base_val = if current.is_a?(String) && current.end_with?('px')
                     current.to_f
                   elsif current.is_a?(Numeric)
                     current.to_f
                   else
                     default_val.to_f
                   end

        acc[key] = "#{(base_val * scale).round}px"
      end

      scaled[:slide_width] = "#{fmt[:width]}px"
      scaled[:slide_height] = "#{fmt[:height]}px"

      base_theme.merge(scaled)
    end

    def build_pdf_document(rendered_html_pages)
      pages = rendered_html_pages.map { |html| extract_body(html) }
      bg = deck_config.dig(:theme, :background_color) || '#ffffff'

      <<~HTML
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="UTF-8">
          <style>
          #{BindingContext.new({}, 0, deck_config).styles}
          html, body {
            margin: 0;
            padding: 0;
            width: auto;
            height: auto;
            overflow: visible;
            background: #{bg};
          }

          @page {
            size: #{page_width_in}in #{page_height_in}in;
            margin: 0;
          }

          .pdf-page {
            width: #{canvas_width}px;
            height: #{canvas_height}px;
            overflow: hidden;
            position: relative;
            page-break-after: always;
            break-after: page;
          }

          .pdf-page:last-child {
            page-break-after: auto;
            break-after: auto;
          }
          </style>
        </head>
        <body>
          #{pages.map { |page| %(<section class="pdf-page">#{page}</section>) }.join("\n")}
        </body>
        </html>
      HTML
    end

    def extract_body(html)
      body = html[/<body[^>]*>(.*)<\/body>/m, 1]
      body ? body.strip : html
    end

    def template_spec(template_name)
      spec = self.class.template_specs[template_name.to_sym]
      raise "Unknown template '#{template_name}'. See templates/catalog.yml for supported layouts." unless spec

      spec
    end

    def value_for_aliases(aliases, slide, raw_content)
      aliases.each do |name|
        key = name.to_sym

        if key == :content && slide[:content].is_a?(String)
          return slide[:content]
        end

        if slide.key?(key) && !blank?(slide[key])
          next if key == :content && slide[key].is_a?(Hash)

          return slide[key]
        end

        return raw_content[key] if raw_content.key?(key) && !blank?(raw_content[key])
      end

      nil
    end

    def relative_to_asset_root(path)
      full = File.expand_path(path)
      root = File.expand_path(asset_root) + '/'
      full.start_with?(root) ? full.delete_prefix(root) : full
    end

    def write_resolved_deck
      ext = File.extname(deck_path)
      resolved_path = deck_path.sub(/#{Regexp.escape(ext)}\z/, ".resolved#{ext}")
      data = YAML.safe_load(File.read(deck_path), permitted_classes: [Symbol])

      slide_data = data.is_a?(Array) ? data : data['slides']
      slides.each_with_index do |slide, i|
        next if slide[:image].nil?
        next unless slide_data[i]

        if slide_data[i]['content'].is_a?(Hash)
          slide_data[i]['content']['image'] = slide[:image]
        else
          slide_data[i]['image'] = slide[:image]
        end
      end

      File.write(resolved_path, ext == '.json' ? JSON.pretty_generate(data) + "\n" : YAML.dump(data))
      puts "Wrote resolved deck: #{resolved_path}"
    end

    def normalize_social_formats(formats)
      return [] if formats.nil?

      values = Array(formats).map(&:to_s)
      invalid = values - SOCIAL_FORMATS.keys
      raise "Unknown social format(s): #{invalid.join(', ')}. Valid: #{SOCIAL_FORMATS.keys.join(', ')}" unless invalid.empty?

      values
    end

    def normalize_output_formats(formats)
      values =
        case formats
        when nil
          DEFAULT_OUTPUT_FORMATS
        when String, Symbol
          formats.to_s.split(',').map(&:strip)
        when Array
          formats.map(&:to_s)
        else
          raise "Unsupported output format declaration: #{formats.inspect}"
        end

      invalid = values - SUPPORTED_OUTPUT_FORMATS
      raise "Unsupported output format(s): #{invalid.join(', ')}" unless invalid.empty?

      values.empty? ? DEFAULT_OUTPUT_FORMATS : values
    end

    def fetch_hash(source, key)
      value =
        if source.is_a?(Hash)
          source[key] || source[key.to_s]
        else
          nil
        end

      value.is_a?(Hash) ? symbolize_hash(value) : {}
    end

    def symbolize_hash(hash)
      hash.each_with_object({}) do |(key, value), acc|
        acc[key.to_sym] =
          case value
          when Hash
            symbolize_hash(value)
          when Array
            value.map { |item| item.is_a?(Hash) ? symbolize_hash(item) : item }
          else
            value
          end
      end
    end

    def symbolize_hash_or_array(data)
      if data.is_a?(Array)
        data.map { |item| item.is_a?(Hash) ? symbolize_hash(item) : item }
      else
        symbolize_hash(data)
      end
    end

    def blank?(value)
      value.nil? || (value.respond_to?(:strip) && value.strip.empty?)
    end

    def deck_name
      File.basename(deck_path).sub(/(\.resolved)?\.(json|ya?ml)\z/, '')
    end

    # Relative asset paths in a deck (assets/x.png) resolve from the repo that holds it:
    # the parent of its decks/ directory. In-memory decks resolve from the engine.
    def asset_root
      return ENGINE_ROOT unless File.file?(deck_path.to_s)

      dir = File.dirname(File.expand_path(deck_path))
      File.basename(dir) == 'decks' ? File.dirname(dir) : dir
    end

    def canvas_width
      (deck_config.dig(:canvas, :width) || self.class.template_catalog.dig(:canvas, :width)).to_i
    end

    def canvas_height
      (deck_config.dig(:canvas, :height) || self.class.template_catalog.dig(:canvas, :height)).to_i
    end

    def page_height_in
      DEFAULT_PAGE_HEIGHT_IN
    end

    def page_width_in
      ((canvas_width.to_f / canvas_height.to_f) * page_height_in).round(3)
    end

    class BindingContext
      attr_reader :slide, :slide_number, :deck_config

      def initialize(slide, slide_number, deck_config)
        @slide = slide
        @slide_number = slide_number
        @deck_config = deck_config || {}
      end

      def get_binding
        binding
      end

      def styles_path
        STYLES_PATH
      end

      # @import rules must precede every other rule, so brand fonts come first.
      def styles
        [font_imports, File.read(styles_path), theme_override_styles].reject(&:empty?).join("\n")
      end

      # Logo and/or mark text from the deck's brand, pinned bottom-left. Empty without a brand.
      def brand_mark
        brand = deck_config[:brand]
        return '' unless brand && (brand[:logo_path] || brand[:mark])

        parts = []
        if brand[:logo_path]
          parts << <<~HTML.strip
            <img
              src="#{logo_data_uri(brand[:logo_path])}"
              alt=""
            >
          HTML
        end
        parts << %(<span>#{ERB::Util.html_escape(brand[:mark])}</span>) if brand[:mark]

        <<~HTML.strip
          <div
            class="brand-mark"
          >
          #{parts.join("\n")}
          </div>
        HTML
      end

      def markdown(text)
        return '' unless text

        text = text.gsub(/\*\*(.+?)\*\*/, '<strong>\1</strong>')
        text = text.gsub(/\*(.+?)\*/, '<em>\1</em>')
        text = text.gsub(/`(.+?)`/, '<code>\1</code>')

        lines = text.split("\n")
        in_list = false
        table_rows = []
        result = []

        lines.each do |line|
          if line.strip.start_with?('|')
            result << '</ul>' if in_list
            in_list = false
            table_rows << line
            next
          elsif table_rows.any?
            result << table_html(table_rows)
            table_rows = []
          end

          if line.strip.start_with?('- ', '* ')
            result << '<ul>' unless in_list
            in_list = true
            content = line.strip.sub(/^[-*]\s+/, '')
            result << "  <li>#{content}</li>"
          else
            result << '</ul>' if in_list
            in_list = false
            result << "<p>#{line}</p>" unless line.strip.empty?
          end
        end

        result << '</ul>' if in_list
        result << table_html(table_rows) if table_rows.any?
        result.join("\n")
      end

      # Pipe table: first row is the header; a |---| separator row is skipped.
      def table_html(rows)
        cells = rows.map { |row| row.strip.sub(/\A\|/, '').sub(/\|\z/, '').split('|').map(&:strip) }
        cells.reject! { |row| row.all? { |cell| cell.match?(/\A:?-{3,}:?\z/) } }
        header, *body = cells

        html = ['<table>', '  <thead>', '    <tr>']
        header.each { |cell| html << "      <th>#{cell}</th>" }
        html += ['    </tr>', '  </thead>', '  <tbody>']
        body.each do |row|
          html << '    <tr>'
          row.each { |cell| html << "      <td>#{cell}</td>" }
          html << '    </tr>'
        end
        html += ['  </tbody>', '</table>']
        html.join("\n")
      end

      private

      def font_imports
        fonts = deck_config.dig(:brand, :fonts) || []
        fonts.map { |url| %(@import url("#{url}");) }.join("\n")
      end

      # Inlined so Chrome never has to resolve a file path from an about:blank page.
      def logo_data_uri(path)
        mime = { '.png' => 'image/png', '.svg' => 'image/svg+xml', '.jpg' => 'image/jpeg', '.jpeg' => 'image/jpeg' }
        type = mime.fetch(File.extname(path).downcase) { raise "Unsupported logo type: #{path}" }
        "data:#{type};base64,#{Base64.strict_encode64(File.binread(path))}"
      end

      def theme_override_styles
        theme = deck_config[:theme]
        return '' unless theme.is_a?(Hash) && !theme.empty?

        css_vars = theme.map do |key, value|
          next if value.nil?

          css_key = "--#{key.to_s.tr('_', '-')}"
          "#{css_key}: #{value};"
        end.compact

        return '' if css_vars.empty?

        ":root {\n  #{css_vars.join("\n  ")}\n}"
      end
    end
  end
end
