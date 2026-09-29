require_relative 'slide_generator'
require 'rake/testtask'

Rake::TestTask.new(:test) do |t|
  t.libs << 'test'
  t.pattern = 'test/**/*_test.rb'
end

SLIDES_ROOT = __dir__

namespace :slides do
  desc "Generate slides from a deck file"
  task :generate, [:deck_path] do |t, args|
    unless args[:deck_path]
      puts "Usage: rake slides:generate[deck-name]   (or a path to a .json/.yml deck)"
      exit 1
    end

    deck_path = Slides::SlideGenerator.resolve_deck(args[:deck_path])

    # Prefer <deck>.resolved.<ext> if it exists (has generated image paths)
    ext = File.extname(deck_path)
    resolved_path = deck_path.sub(/#{Regexp.escape(ext)}\z/, ".resolved#{ext}")
    if File.exist?(resolved_path)
      puts "Using resolved deck: #{File.basename(resolved_path)}"
      deck_path = resolved_path
    end

    deck_name = File.basename(deck_path).sub(/(\.resolved)?\.(json|ya?ml)\z/, '')
    output_dir = File.join(SLIDES_ROOT, "public/slides/#{deck_name}")

    generator = Slides::SlideGenerator.new(deck_path, output_dir: output_dir)

    if generator.has_unresolved_image_prompts?
      puts "\nWarning: Deck contains image_prompt fields without resolved images."
      puts "Run: rake slides:generate_images[#{args[:deck_path]}]\n\n"
    end

    generator.generate
  end

  desc "Report text that overflows each slide's content box; exits 1 if any"
  task :lint, [:deck_path] do |t, args|
    unless args[:deck_path]
      puts "Usage: rake slides:lint[deck-name]"
      exit 1
    end

    deck_path = Slides::SlideGenerator.resolve_deck(args[:deck_path])
    generator = Slides::SlideGenerator.new(deck_path)
    overflows = generator.lint

    if overflows.empty?
      puts "✓ #{generator.slides.length} slide(s), no overflow: #{File.basename(deck_path)}"
    else
      overflows.group_by { |o| o[:slide_number] }.each do |number, items|
        puts "slide #{number} (#{items.first[:template]}):"
        items.each { |o| puts "  #{Slides::SlideGenerator.describe_overflow(o)}" }
      end
      puts "\n✗ #{overflows.length} overflow(s) on #{overflows.map { |o| o[:slide_number] }.uniq.length} slide(s). Split the slide or pick a denser template."
      exit 1
    end
  end

  desc "Print the supported slide templates and their constraints"
  task :catalog do
    catalog = Slides::SlideGenerator.template_catalog

    puts "Canvas: #{catalog.dig(:canvas, :width)}x#{catalog.dig(:canvas, :height)} (#{catalog.dig(:canvas, :aspect_ratio)})"
    puts "Canonical template language: #{catalog.dig(:authoring, :canonical_template_language)}"
    puts "Export formats: #{Array(catalog.dig(:authoring, :export_formats)).join(', ')}"
    puts

    Slides::SlideGenerator.template_specs.each do |name, spec|
      puts "#{name}: #{spec[:description]}"
      puts "  Required: #{Array(spec[:required_fields]).join(', ')}" unless Array(spec[:required_fields]).empty?
      puts "  Optional: #{Array(spec[:optional_fields]).join(', ')}" unless Array(spec[:optional_fields]).empty?
      puts "  Best for: #{Array(spec[:best_for]).join(', ')}" unless Array(spec[:best_for]).empty?

      Array(spec[:constraints]).each do |constraint|
        puts "  Constraint: #{constraint}"
      end

      Array(spec[:regions]).each do |region_name, region_spec|
        puts "  Region #{region_name}: #{region_spec[:description]}"
      end

      puts
    end
  end

  desc "Print a prompt-ready description of supported templates for LLM use"
  task :prompt_context do
    puts Slides::SlideGenerator.prompt_context
  end

  desc "Generate manifest.json for the slide viewer SPA"
  task :manifest do
    require 'json'

    decks_dir = File.join(Slides::SlideGenerator.decks_dir, 'decks')
    public_dir = File.join(SLIDES_ROOT, 'public')
    slides_dir = File.join(public_dir, 'slides')

    # Symlink decks/ into public/ so the SPA can fetch YAML
    public_decks = File.join(public_dir, 'decks')
    unless File.exist?(public_decks)
      File.symlink(decks_dir, public_decks)
      puts "Symlinked #{public_decks} → #{decks_dir}"
    end

    decks = Slides::SlideGenerator.deck_paths.map do |path|
      name = File.basename(path, '.*')
      output = File.join(slides_dir, name)
      slide_count = Dir.glob(File.join(output, 'slide_*.png')).length

      { name: name, slide_count: slide_count }
    end.select { |d| d[:slide_count] > 0 }

    manifest = { generated_at: Time.now.strftime('%Y-%m-%dT%H:%M:%S%z'), decks: decks }
    manifest_path = File.join(public_dir, 'manifest.json')
    File.write(manifest_path, JSON.pretty_generate(manifest))
    puts "Wrote #{manifest_path} (#{decks.length} decks)"
  end

  desc "Generate a single image from a prompt via OpenAI"
  task :generate_image, [:prompt] do |t, args|
    unless args[:prompt]
      puts "Usage: rake slides:generate_image[\"a watercolor city hall\"]"
      exit 1
    end

    require_relative 'lib/image_generator'
    result = Slides::ImageGenerator.generate(args[:prompt])
    if result
      puts "\n✓ Generated: #{result[:file]}"
    else
      puts "\n✗ Image generation failed."
      exit 1
    end
  end

  desc "Generate all images from image_prompt fields in a deck, write .resolved.yml"
  task :generate_images, [:deck_path] do |t, args|
    unless args[:deck_path]
      puts "Usage: rake slides:generate_images[deck-name]"
      exit 1
    end

    deck_path = Slides::SlideGenerator.resolve_deck(args[:deck_path])
    generator = Slides::SlideGenerator.new(deck_path)

    unless generator.has_unresolved_image_prompts?
      puts "No unresolved image_prompt fields found."
      exit 0
    end

    generator.resolve_image_prompts!
    puts "\n✓ Image prompts resolved. Resolved deck written."
  end

  desc "Export slides at a social media format (twitter, linkedin, og, square)"
  task :social, [:deck_path, :format] do |t, args|
    unless args[:deck_path] && args[:format]
      puts "Usage: rake slides:social[deck-name,twitter]"
      puts "Formats: #{Slides::SlideGenerator::SOCIAL_FORMATS.keys.join(', ')}"
      exit 1
    end

    deck_path = Slides::SlideGenerator.resolve_deck(args[:deck_path])
    deck_name = File.basename(deck_path, '.*')
    output_dir = File.join(SLIDES_ROOT, "public/slides/#{deck_name}")

    generator = Slides::SlideGenerator.new(deck_path, output_dir: output_dir)
    generator.generate_social(args[:format])
  end

  desc "Render a standalone ERB template to PNG at custom dimensions"
  task :render, [:template_path, :output_path, :width, :height] do |t, args|
    unless args[:template_path] && args[:output_path]
      puts "Usage: rake slides:render[path/to/diagram.html.erb,output.png,900,400]"
      exit 1
    end

    require 'erb'
    require 'grover'

    template_path = File.expand_path(args[:template_path], SLIDES_ROOT)
    output_path = File.expand_path(args[:output_path], SLIDES_ROOT)
    width = (args[:width] || 900).to_i
    height = (args[:height] || 400).to_i

    template = File.read(template_path)
    html = ERB.new(template).result

    FileUtils.mkdir_p(File.dirname(output_path))
    grover = Grover.new(html, format: 'png', viewport: { width: width, height: height })
    File.binwrite(output_path, grover.to_png)
    puts "Rendered: #{output_path} (#{width}x#{height})"
  end

  desc "List brands (brands/<name>/brand.yml)"
  task :brands do
    Slides::SlideGenerator.brand_names.each do |name|
      brand = Slides::SlideGenerator.load_brand(name)
      puts "#{name}: #{brand[:description] || brand[:name]}"
    end
  end

  desc "Render a brand sheet (swatches, type, every template) to public/sheets/<brand>.png; no arg = all brands"
  task :sheet, [:brand] do |t, args|
    require_relative 'lib/brand_sheet'

    names = args[:brand] ? [args[:brand]] : Slides::SlideGenerator.brand_names
    names.each do |name|
      paths = Slides::BrandSheet.new(name, output_dir: File.join(SLIDES_ROOT, 'public/sheets')).generate
      paths.each do |path|
        raise "Brand sheet not written: #{path}" unless File.size?(path)

        puts "✓ #{path} (#{File.size(path)} bytes)"
      end
    end
  end

  desc "Write public/js/engine-data.js (styles, catalog, brands) for the editor site"
  task :site do
    require_relative 'lib/site_bundle'

    path = Slides::SiteBundle.write
    raise "engine-data.js not current after write: #{path}" unless Slides::SiteBundle.current?

    puts "✓ #{path} (#{File.size(path)} bytes)"
  end

  desc "List available slide decks"
  task :list do
    decks = Slides::SlideGenerator.deck_paths
    if decks.empty?
      puts "No decks found in #{Slides::SlideGenerator.decks_dir}/decks"
    else
      puts "Decks in #{Slides::SlideGenerator.decks_dir}/decks:"
      decks.each do |deck|
        puts "  - #{File.basename(deck, '.*')}"
      end
    end
  end

  desc "Write index.json in the decks repo (one entry per deck, from deck data alone)"
  task :index do
    require_relative 'lib/deck_index'

    path = Slides::DeckIndex.write
    count = JSON.parse(File.read(path))['decks'].length
    raise "index.json lists #{count} decks, expected #{Slides::SlideGenerator.deck_paths.length}" unless count == Slides::SlideGenerator.deck_paths.length

    puts "✓ #{path} (#{count} decks)"
  end
end
