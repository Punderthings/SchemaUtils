#!/usr/bin/env ruby
module SchemaUtils
  DESCRIPTION = <<-HEREDOC
  Transform a JSON Schema into Jekyll Liquid template includes and template.md files.
  HEREDOC

  module_function
  require 'yaml'
  require 'json'
  require 'optparse'

  # Tokens for processing schema properties when type=string, format=jjresolver~...
  JJRESOLVER_TYPE = 'jjresolver'
  JJRESOLVER_SEP = '~'
  JJ_COLLECTION = 'jjcollection'
  JJ_SELECTOR = 'jjselector'
  JJ_FIELD = 'jjfield'
  JJ_BASEURL = 'jjbaseurl'
  # Token for type=string, format=urlfragment~https://punderthings.github.io/SchemaUtils/
  URLFRAGMENT_TYPE = 'urlfragment'

  # @!group Liquid emitters
  # Emit liquid statements for jjresolver per-array maps
  # @param resolver Hash of a parsed jjresolver entry
  # @return String fragment of pre-loop liquid mapping
  def emit_jjresolver_map1(resolver)
    return "{% assign jjmapping = site['#{resolver[JJ_COLLECTION]}'] %}"
  end

  # Emit liquid statements for jjresolver per-array-item map
  # @param fieldname String current document fieldname
  # @param resolver Hash of a parsed jjresolver entry
  # @return String fragment of in-loop liquid mapping
  def emit_jjresolver_map2(fieldname, resolver)
    return "{% assign jjlinkmap = jjmapping | where: '#{resolver[JJ_SELECTOR]}', #{fieldname} | first %}"
  end

  # Emit liquid statements for jjresolver single data item
  # @param fieldname String current document fieldname
  # @param resolver Hash of a parsed jjresolver entry
  # @param fallback String of fallback value if mapping not found at runtime
  # @return String fragment of liquid statements
  def emit_jjresolver_value(fieldname, resolver, fallback)
    liquid = "{% if jjlinkmap %}"
    liquid << "<span itemprop=\"#{fieldname}\"><a href=\"#{resolver[JJ_BASEURL]}{{ jjlinkmap['#{resolver[JJ_SELECTOR]}'] }}\">{{ jjlinkmap['#{resolver[JJ_FIELD]}'] }}</a></span>"
    liquid << "{% else %}"
    liquid << "<span itemprop=\"#{fieldname}\">{{ #{fallback} }}</span>"
    liquid << "{% endif %}"
  end

  # Emit liquid template for a single value
  # @param fieldname String of this schema object
  # @param schema Hash to process and emit liquid for
  # @return String fragment of liquid statement
  def emit_schema_valuespan(fieldname, schema)
    liquid = ''
    page_fieldname = "page.#{fieldname}"
    format = schema.fetch('format', '').split(JJRESOLVER_SEP)
    if 'url'.eql?(format[0])
      liquid << "<a itemprop=\"#{fieldname}\" href=\"{{ #{page_fieldname} }}\">{{ #{page_fieldname} }}</a>"
    elsif URLFRAGMENT_TYPE.eql?(format[0])
      liquid << "<a itemprop=\"#{fieldname}\" href=\"#{format[1]}{{ #{page_fieldname} }}\">{{ #{page_fieldname} }}</a>"
    elsif schema.key?(JJRESOLVER_TYPE)
      resolver = schema[JJRESOLVER_TYPE]
      liquid << emit_jjresolver_map1(resolver)
      liquid << emit_jjresolver_map2(page_fieldname, resolver)
      liquid << emit_jjresolver_value(fieldname, resolver, page_fieldname)
    else
      liquid << "<span itemprop=\"#{fieldname}\">{{ #{page_fieldname} }}</span>"
    end
    return liquid
  end

  # Emit liquid template for a scalar field
  # @param parentname String of parent schema object that contains this object
  # @param fieldname String of this schema object
  # @param schema Hash to process and emit liquid for
  # @param indent String for use at this level
  # @param linesep String for use if needed
  # @return String line of liquid statements
  def emit_schema_scalar(parentname, fieldname, schema, indent, linesep)
    qualified_name = parentname ? "#{parentname}.#{fieldname}" : fieldname
    liquid = "#{indent}{% if page.#{qualified_name} %}"
    liquid << "<abbr title=\"#{schema['description']}\">#{schema['title']}</abbr>: "
    liquid << emit_schema_valuespan(qualified_name, schema)
    liquid << "#{linesep}" if linesep
    liquid << "{% endif %}\n"
    return liquid
  end

  LOOPITEM = 'loopitem'
  # Emit liquid template for array as a title and ul list
  # @param fieldname String of this schema object
  # @param schema Hash to process and emit liquid for
  # @param indent String for use at this level
  # @param linesep String for use if needed
  # @return String lines of liquid statements
  def emit_schema_array(fieldname, schema, indent, linesep)
    page_fieldname = "page.#{fieldname}"
    liquid = "#{indent}{% if #{page_fieldname} %}\n"
    liquid << "#{indent}<abbr title=\"#{schema['description']}\">#{schema['title']}</abbr>:\n"
    liquid << "#{indent}<ul>\n" # TODO: add class for styling
    items = schema['items']
    resolver = items.key?(JJRESOLVER_TYPE) ? items[JJRESOLVER_TYPE] : nil
    format = items.fetch('format', '').split(JJRESOLVER_SEP)
    if resolver
      liquid << emit_jjresolver_map1(resolver)
      liquid << "\n"
    end
    liquid << "#{indent}  {% for #{LOOPITEM} in #{page_fieldname} %}\n"
    liquid << "#{indent}  <li>"
    if resolver
      liquid << emit_jjresolver_map2(LOOPITEM, resolver)
      liquid << emit_jjresolver_value(fieldname, resolver, LOOPITEM)
    elsif 'url'.eql?(format[0])
      liquid << "<a itemprop=\"#{fieldname}\" href=\"{{ loopitem }}\">{{ loopitem }}</a>"
    elsif URLFRAGMENT_TYPE.eql?(format[0])
      liquid << "<a itemprop=\"#{fieldname}\" href=\"#{format[1]}{{ loopitem }}\">{{ loopitem }}</a>"
    else
      liquid << "<span itemprop=\"#{fieldname}\">{{ loopitem }}</span>"
    end
    liquid << "</li>\n"
    liquid << "#{indent}  {% endfor %}\n"
    liquid << "#{indent}</ul>\n"
    liquid << "#{indent}#{linesep}" if linesep
    liquid << "{% endif %}\n"
    return liquid
  end

  # Emit liquid template for nested hash/array schema objects (recursive)
  # FIXME: for truly proper recursive processing and indent management
  # @param parentname String of parent schema object that contains other objects
  # @param fieldname String of this schema object
  # @param schema Hash to process and emit liquid for
  # @param indent String for use at this level
  # @param linesep String for use if needed
  # @return String lines of various liquid statements
  def emit_schema_object(parentname, childname, schema, indent, linesep)
    liquid = ''
    name_hack = parentname ? "#{parentname}.#{childname}" : childname
    properties = schema['properties']
    properties.each do |itmname, hash|
      if 'object'.eql?(hash['type'])
        liquid << "#{indent}{% if page.#{name_hack}.#{childname}.#{itmname} %}\n"
        liquid << emit_schema_object(name_hack, itmname, hash, indent, linesep)
        liquid << linesep if linesep
        liquid << "{% endif %}\n"
      elsif 'array'.eql?(hash['type'])
        liquid << emit_schema_array(fieldname, hash, indent, linesep)
      else
        liquid << emit_schema_scalar(name_hack, itmname, hash, indent, linesep)
      end
    end
    return liquid
  end

  # @!group Transform Schemas
  # Transform JSON Schema into partial Jekyll Liquid templates
  # FIXME: indenting, linesep are not consistent
  # @param schema Hash to process and emit liquid for
  # @param linesep String for use if needed
  # @return String lines of a liquid _include document
  def schema2liquid(schema, linesep)
    liquid = ''
    indent = '    ' # FIXME if we want to nest inside existing layout
    fieldnames = []
    properties = schema['properties']
    firstsection = true
    properties.each do |fieldname, hash|
      fieldnames << fieldname
      section = hash.fetch('section', nil)
      if section
        if firstsection
          firstsection = false
        else
          liquid << "  </section>\n"
        end
        liquid << "  <section id=\"#{section.downcase}-section\">\n"
        liquid << "#{indent}<h2 id=\"#{section.downcase}\">#{section}</h2>\n"
      end
      if 'object'.eql?(hash['type'])
        liquid << emit_schema_object(nil, fieldname, hash, indent, linesep)
      elsif 'array'.eql?(hash['type'])
        liquid << emit_schema_array(fieldname, hash, indent, linesep)
      else
        liquid << emit_schema_scalar(nil, fieldname, hash, indent, linesep)
      end
    end
    liquid << "  </section>\n"
    puts "DEBUG: List of fieldnames parsed:"
    puts "#{fieldnames}"
    return liquid
  end

  # Transform JSON Schema into template.md file for the type
  # @param schema Hash to process and emit liquid for
  # @param linesep String for use if needed
  # @return String lines of a Jekyll markdown _data document
  def schema2template(schema, body)
    template = "---\n"
    properties = schema['properties']
    properties.each do |fieldname, hash|
      next if hash.fetch('$comment', '').start_with?('EXCLUDE')
      template << "#{fieldname}: # #{hash.fetch('title', '')}\n"
    end
    template << "---\n\n#{body}\n"
    return template
  end

  # @!group Schema parsing
  # Pre-process any Schema properties with type=string, format="jjresolver~..."
  # @param property hash of this schema property
  # NOTE: modifies property in place
  # FIXME: does not yet recurse to handle objects
  def parse_jjresolver!(property)
    mutate = 'array'.eql?(property['type']) ? property['items'] : property
    if 'string'.eql?(mutate['type'])
      format = mutate.fetch('format', '').split(JJRESOLVER_SEP)
      if JJRESOLVER_TYPE.eql?(format[0])
        mutate[JJRESOLVER_TYPE] = {
          JJ_COLLECTION => format[1],
          JJ_SELECTOR => format[2],
          JJ_FIELD => format[3],
          JJ_BASEURL => format[4]
        }
      end
    end
  end

  # Parse a JSON Schema file into a hash
  def parse_schema(infile)
    schema = JSON.parse(File.read(infile))
    schema['properties'].each do |fieldname, hash|
      parse_jjresolver!(hash) # Mutates in place
    end
    return schema
  end

  # ## ### #### ##### ######
  # @!group Command line
  # Check commandline options
  def parse_commandline
    options = {}
    OptionParser.new do |opts|
      opts.on('-h', '--help') { puts "#{DESCRIPTION}\n#{opts}"; exit }
      opts.on('-oOUTFILE', '--out OUTFILE', 'Output filename Jekyll _include file') do |out|
        options[:out] = out
      end
      opts.on('-tTEMPLATEOUT', '--template TEMPLATEOUT', 'Output filename for template.md data') do |outtemplate|
        options[:outtemplate] = outtemplate
      end
      opts.on('-iINFILE', '--in INFILE', 'Input filename of schema.json for processing') do |infile|
        options[:infile] = infile
      end
      begin
        opts.parse!
      rescue OptionParser::ParseError => e
        $stderr.puts e
        $stderr.puts opts
        exit 1
      end
    end
    return options
  end

  # ### #### ##### ######
  # Main method for command line use
  if __FILE__ == $PROGRAM_NAME
    options = parse_commandline
    options[:infile] ||= '_test/testdata-schema.json'
    options[:out] ||= '_includes/testdata-fields.html'
    options[:outtemplate] ||= '_test/testdata-template.md'
    options[:linesep] ||= '<br/>'
    options[:bodytemplate] ||= 'BODY_TEMPLATE This template is used for the {{ content }} of each template file (after frontmatter).'
    puts "BEGIN #{__FILE__}.schema2liquid(#{options[:infile]}, #{options[:linesep]})"
    schema = parse_schema(options[:infile])
    lines = schema2liquid(schema, options[:linesep])
    File.write(options[:out], lines)
    puts "...wrote liquid to #{options[:out]}; WARNING: manual tweaking likely needed"
    lines = schema2template(schema, options[:bodytemplate])
    File.write(options[:outtemplate], lines)
    puts "END wrote template to #{options[:outtemplate]}"
  end
end
