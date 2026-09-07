# frozen_string_literal: true

require "jekyll"
require "date"
require "pathname"

# Validate drafts too: malformed drafts should be caught before publication.
root = Pathname.new(ARGV.fetch(0, ".")).expand_path
config = Jekyll.configuration("source" => root.to_s, "quiet" => true)
site = Jekyll::Site.new(config)
errors = []
checked = 0
paths = Dir.glob(root.join("{_posts,_drafts}/**/*.{md,markdown}").to_s).sort
paths.each do |filename|
  path = Pathname.new(filename).relative_path_from(root).to_s
  next if path.split("/").any? { |part| part.start_with?(".") }
  next if config.fetch("exclude", []).any? { |pattern| File.fnmatch?(pattern, path) }

  checked += 1
  if path.start_with?("_posts/")
    name = File.basename(path)
    begin
      raise ArgumentError unless name.match?(/\A\d{4}-\d{2}-\d{2}-.+\.(md|markdown)\z/)
      Date.iso8601(name[0, 10])
    rescue ArgumentError
      errors << "#{path}:1: Article filename must be YYYY-MM-DD-title.md with a valid date"
    end
  end
  lines = File.readlines(filename, encoding: "bom|utf-8")
  ending = (1...lines.length).find { |i| lines[i].strip == "---" }
  unless lines.first&.strip == "---" && ending
    errors << "#{path}:1: Missing or unclosed YAML front matter"
    next
  end

  begin
    metadata = YAML.safe_load(lines[1...ending].join, permitted_classes: [Date, Time], aliases: true)
    raise ArgumentError, "Front matter must be a mapping" unless metadata.is_a?(Hash)
    raise ArgumentError, "title must be a nonempty string" unless metadata["title"].is_a?(String) && !metadata["title"].strip.empty?
    %w[published toc mermaid].each do |key|
      next unless metadata.key?(key)
      raise ArgumentError, "#{key} must be true or false, without quotes" unless [true, false].include?(metadata[key])
    end
    %w[categories tags].each do |key|
      next unless metadata.key?(key)
      value = metadata[key]
      valid = value.is_a?(String) || (value.is_a?(Array) && value.all? { |item| item.is_a?(String) })
      raise ArgumentError, "#{key} must be a string or a list of strings" unless valid
    end
    Jekyll::Utils.parse_date(metadata["date"].to_s, "Invalid article date") if metadata.key?("date")
  rescue Psych::Exception, ArgumentError, TypeError, Jekyll::Errors::FatalException => e
    errors << "#{path}:2: #{e.message}"
    next
  end

  body = lines[(ending + 1)..].join
  # Kramdown treats an unclosed fence as prose, so check fences before its AST.
  fence = nil
  body.each_line.with_index(ending + 2) do |line, number|
    if fence
      fence = nil if line.match?(/^\s{0,3}#{Regexp.escape(fence[:char])}{#{fence[:length]},}\s*$/)
    elsif (match = line.match(/^\s{0,3}(`{3,}|~{3,})(.*)$/))
      fence = { char: match[1][0], length: match[1].length, line: number }
    end
  end
  errors << "#{path}:#{fence[:line]}: Unclosed code fence" if fence

  type = path.start_with?("_drafts/") ? :drafts : :posts
  defaults = site.frontmatter_defaults.all(path, type)
  mermaid_enabled = defaults.merge(metadata)["mermaid"] == true
  document = Kramdown::Document.new(body, **config.fetch("kramdown").transform_keys(&:to_sym))
  visit = lambda do |element|
    if element.type == :codeblock
      number = ending + 1 + element.options.fetch(:location, 1)
      lang = element.options[:lang].to_s
      if lang.empty?
        errors << "#{path}:#{number}: Code block needs a language (bash, text, mermaid, etc.)"
      elsif lang == "mermaid"
        errors << "#{path}:#{number}: Mermaid diagram requires mermaid: true" unless mermaid_enabled
      elsif %w[text plaintext].include?(lang) && element.value.lstrip.match?(/\A(?:flowchart|graph|sequenceDiagram|stateDiagram(?:-v2)?|classDiagram|erDiagram|gitGraph|mindmap|gantt|pie|timeline)\b/)
        errors << "#{path}:#{number}: Mermaid syntax is inside a #{lang} block; use mermaid"
      end
    end
    element.children.each { |child| visit.call(child) }
  end
  visit.call(document.root)
end

abort errors.join("\n") unless errors.empty?
puts "Article checks passed (#{checked} articles, including drafts)."
