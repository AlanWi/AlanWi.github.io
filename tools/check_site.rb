# frozen_string_literal: true

require "nokogiri"
require "json"
require "pathname"
require "uri"
require "yaml"

destination = Pathname.new(ARGV.fetch(0, ".jekyll-check")).expand_path
abort "Build directory does not exist: #{destination}" unless destination.directory?
config = YAML.safe_load_file("_config.yml")
site_host = URI(config.fetch("url")).host
baseurl = config.fetch("baseurl", "").sub(%r{/$}, "")
errors = []
diagrams = []
pages = Dir.glob(destination.join("**/*.html").to_s)
abort "No HTML pages found in #{destination}" if pages.empty?
pages.each do |filename|
  path = Pathname.new(filename)
  relative = path.relative_path_from(destination).to_s
  html = Nokogiri::HTML(File.read(path))
  html.css("img[src]").each do |img|
    src = img["src"].strip
    next if src.start_with?("data:", "blob:")
    begin
      uri = URI.parse(URI::DEFAULT_PARSER.escape(src, /[^\x21-\x7E]/))
      next if uri.host && uri.host != site_host
      next if uri.scheme && !%w[http https].include?(uri.scheme)

      image_path = URI::DEFAULT_PARSER.unescape(uri.path.to_s)
      if image_path.start_with?("/")
        image_path = image_path.delete_prefix(baseurl) if !baseurl.empty? && image_path.start_with?("#{baseurl}/")
        target = destination.join(image_path.delete_prefix("/")).cleanpath
      else
        target = path.dirname.join(image_path).cleanpath
      end
      unless !image_path.empty? && target.to_s.start_with?("#{destination}/") && target.file?
        errors << "#{relative}: Missing local image: #{src}"
      end
    rescue URI::InvalidURIError => e
      errors << "#{relative}: Invalid image URL #{src.inspect}: #{e.message}"
    end
  end
  html.css(".language-mermaid").each_with_index do |element, i|
    code = element.at_css("code") || element
    diagrams << { page: relative, diagram: i + 1, code: code.text }
  end
end
abort errors.join("\n") unless errors.empty?
File.write(destination.join("mermaid.json"), JSON.pretty_generate(diagrams))
puts "Local image checks passed (#{pages.size} HTML pages); #{diagrams.size} Mermaid diagrams queued."
