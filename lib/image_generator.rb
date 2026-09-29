require "net/http"
require "json"
require "fileutils"
require "base64"
require "uri"
require "time"

module Slides
  module ImageGenerator
    # Default only for standalone `rake slides:generate_image`; deck resolution passes the deck repo's assets/generated.
    OUTPUT_DIR = File.expand_path("public/images", File.join(File.dirname(__FILE__), ".."))
    MANIFEST_PATH = File.join(OUTPUT_DIR, "manifest.json")
    API_URL = URI("https://api.openai.com/v1/images/generations")

    module_function

    def generate(prompt, label: nil, size: "1024x1024", output_dir: OUTPUT_DIR)
      FileUtils.mkdir_p(output_dir)

      api_key = ENV["OPENAI_API_KEY"]
      unless api_key && !api_key.empty?
        raise "OPENAI_API_KEY is not set. Export it or add it via direnv."
      end

      timestamp = Time.now.strftime("%Y%m%d-%H%M%S")
      slug = (label || prompt).downcase.gsub(/[^a-z0-9]+/, "-")[0, 60].chomp("-")
      filename = "#{timestamp}-#{slug}.png"
      filepath = File.join(output_dir, filename)

      puts "Generating: #{prompt[0, 80]}..."

      body = {
        model: "gpt-image-1",
        prompt: prompt,
        size: size,
        quality: "high",
        n: 1,
        output_format: "png"
      }

      http = Net::HTTP.new(API_URL.host, API_URL.port)
      http.use_ssl = true
      http.read_timeout = 180

      request = Net::HTTP::Post.new(API_URL)
      request["Authorization"] = "Bearer #{api_key}"
      request["Content-Type"] = "application/json"
      request.body = JSON.generate(body)

      response = http.request(request)
      data = JSON.parse(response.body)

      if data["error"]
        warn "  ERROR: #{data['error']['message']}"
        return nil
      end

      image_data_b64 = data.dig("data", 0, "b64_json")
      revised = data.dig("data", 0, "revised_prompt")

      if image_data_b64
        image_data = Base64.decode64(image_data_b64)
      else
        url = data.dig("data", 0, "url")
        unless url
          warn "  ERROR: No image in response"
          warn "  Response: #{data.to_json[0, 300]}"
          return nil
        end
        image_data = Net::HTTP.get(URI(url))
      end

      File.binwrite(filepath, image_data)

      puts "  Saved: #{filepath}"
      puts "  Revised prompt: #{revised}" if revised && revised != prompt

      result = {
        prompt: prompt,
        model: "gpt-image-1",
        revised_prompt: revised,
        file: filepath,
        filename: filename,
        created_at: Time.now.iso8601
      }

      append_manifest(result, output_dir)
      result
    end

    def load_manifest(output_dir: OUTPUT_DIR)
      path = File.join(output_dir, "manifest.json")
      File.exist?(path) ? JSON.parse(File.read(path)) : []
    end

    def append_manifest(entry, output_dir = OUTPUT_DIR)
      path = File.join(output_dir, "manifest.json")
      existing = File.exist?(path) ? JSON.parse(File.read(path)) : []
      existing << entry.transform_keys(&:to_s)
      File.write(path, JSON.pretty_generate(existing))
    end
  end
end
