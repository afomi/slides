require 'json'
require 'open3'
require 'tmpdir'

module Slides
  # Ruby side of lib/render.cjs: writes each job's HTML to a temp file, renders the whole batch
  # in one Chrome, and confirms every artifact exists and is non-empty before reporting success.
  class Renderer
    ROOT = File.expand_path('..', __dir__)
    SCRIPT = File.join(__dir__, 'render.cjs')
    DEFAULT_TIMEOUT_MS = 60_000

    class RenderError < StandardError; end

    Job = Struct.new(:html, :out, :format, :width, :height, :full_page, :measure, keyword_init: true)

    # jobs: [Job]; returns [{ 'id', 'ok', 'out', 'bytes', 'overflows', 'error' }] in job order.
    # Raises RenderError listing every failed job; successful artifacts are still written.
    # root: where relative asset paths resolve (the deck's repo); defaults to the engine.
    def self.render(jobs, root: ROOT, timeout_ms: DEFAULT_TIMEOUT_MS)
      return [] if jobs.empty?

      Dir.mktmpdir('slides-render') do |dir|
        payload = jobs.each_with_index.map do |job, index|
          html_path = File.join(dir, "job_#{index}.html")
          File.write(html_path, job.html)
          FileUtils.mkdir_p(File.dirname(job.out)) if job.out

          {
            id: index,
            html_path: html_path,
            out: job.out && File.expand_path(job.out),
            format: job.format || 'png',
            width: job.width,
            height: job.height,
            full_page: job.full_page,
            measure: job.measure
          }
        end

        stdout, stderr, status = Open3.capture3(
          'node', SCRIPT,
          stdin_data: JSON.generate(root: File.expand_path(root), timeout: timeout_ms, jobs: payload),
          chdir: ROOT
        )

        results = stdout.lines.filter_map { |line| JSON.parse(line) rescue nil }
        if results.length != jobs.length
          raise RenderError, "Renderer returned #{results.length}/#{jobs.length} results " \
                             "(exit #{status.exitstatus}).\n#{stderr.strip}"
        end

        failures = results.reject { |result| result['ok'] }
        results.each do |result|
          next unless result['ok'] && result['out'] && payload[result['id']][:format] != 'none'
          next if File.size?(result['out'])

          failures << result.merge('error' => "renderer reported success but #{result['out']} is missing or empty")
        end

        unless failures.empty?
          detail = failures.map { |failure| "  job #{failure['id']} → #{failure['out'] || 'measure'}: #{failure['error']}" }
          raise RenderError, "#{failures.length} of #{jobs.length} render job(s) failed:\n#{detail.join("\n")}"
        end

        results
      end
    end
  end
end
