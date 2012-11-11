#!/usr/bin/env ruby

require 'pathname'
require 'tempfile'
require 'json'
require 'uri'
require 'optparse'
require 'mime/types'

#
# Modify below constants for your system
#
JS_BIN = "js"
CURL_BIN = "curl"
COUCH_URL="http://localhost:5984/sedis"

#
# Do not modify below this -- cinsk
#
JS_HEADER = "var _sum = function(keys, values, rereduce) { return 0; }
var _count = function(keys, values, rereduce) { return 0; }
var _stats = function(keys, values, rereduce) { return 0; }
var func = \n"
JS_FOOTER = "\nprint(func)"

VERSION="0.2"

DEBUG=false

PROGRAM_NAME = File.basename($PROGRAM_NAME)

def log(message)
  if DEBUG
    puts message
  end
end

def error(message, prefix = "")
  if prefix.size == 0
    STDERR.write("#{PROGRAM_NAME}: #{message}\n")
  else
    STDERR.write("#{PROGRAM_NAME}:#{prefix}: #{message}\n")
  end
end

def verbose(message)
  puts message if Options.verbose
end

def src_error(message)
  STDERR.write("#{message}\n")
end


class CurlResponse
  @@body_separator = "\r\n\r\n"

  @@curl_status = {
    1 => "unsupported protocol",
    2 => "failed to initialized",
    3 => "malformed URL",
    4 => "disabled feature",
    5 => "couldn't resolve the proxy",
    6 => "couldn't resolve the host",
    7 => "failed to connect to host",
    18 => "partial file",
    23 => "write error",
    26 => "read error",
    27 => "out of memory",
    28 => "operation timeout",
    33 => "HTTP range error",
    34 => "HTTP post error",
    35 => "SSL connect error",
    37 => "can't open the file",
    43 => "internal error",
    45 => "interface error",
    47 => "too many redirect",
    48 => "invalid options",
    51 => "the peer's SSL certificate was not OK",
    52 => "no reply",
    53 => "SSL crypto engine not found",
    54 => "cannot set SSL crypto engine as default",
    55 => "failed sending network data",
    56 => "failed in receiving network data",
    58 => "local certificate problem",
    59 => "couldn't use specified SSL cipher",
    60 => "unknown CA certificate from the peer",
    61 => "unrecognized transfer encoding",
    63 => "maximum file size exceeded",
    67 => "user name/password was not accepted"
  }

  attr_accessor :headers, :body

  def initialize(headers, body)
    @headers = headers
    @body = body
  end

  def self.error_message(code)
    if @@curl_status[code] != nil
      "#{code}: #{@@curl_status[code]}"
    else
      "#{code}: see the man page of curl(1)"
    end
  end

  def self.build(resp)
    raise self.error_message($?.exitstatus) if $?.exitstatus != 0

    idx = resp.index(@@body_separator)

    if idx != nil
      headers = resp[0...idx]
      body = resp[(idx + @@body_separator.size)..-1]

      #puts "old header: #{headers}"
      while true
        if /^HTTP\/[0-9.]+ +[0-9]+ +.*/.match(body)
          idx = body.index(@@body_separator)
          break if idx == nil
          headers = body[0...idx]
          #puts "new header: #{headers}"
          body = body[(idx + @@body_separator.size)..-1]
        else
          break
        end
      end
    else
      headers = resp
      body = nil
    end

    parsed = {}
    in_headers = headers.split("\r\n")

    m = /HTTP\/[0-9.]+ +([0-9]+) +.*/.match(in_headers[0])
    parsed["Status"] = m[1] if m != nil

    in_headers[1..-1].each { |hd|
      m = /^([^:]+): *(.*)/.match(hd)
      parsed[m[1]] = m[2]
    }

    CurlResponse.new(parsed, body)
  end
end

class Curl
  def self.head(url)
    cmdline = "#{CURL_BIN} -s -L -I '#{url}'"

    CurlResponse.build(`#{cmdline}`)
  end

  def self.build_params(params = {})
    return "" if params.size == 0

    retval = ""
    params.each_pair { |k, v|
      retval += "&#{URI.escape(k.to_s)}=#{URI.escape(v.to_s)}"
    }
    "?" + retval[1..-1]
  end

  def self.get(url, params = {}, headers = {})
    cmdline = "#{CURL_BIN} -s -i -L"

    headers.each_pair { |k, v|
      cmdline += " -H '#{k}: #{v}'"
    }

    cmdline += " '#{url}#{self.build_params(params)}'"

    #log("GET: #{cmdline}");
    CurlResponse.build(`#{cmdline}`)
  end

  def self.delete(url, params = {}, headers = {})
    cmdline = "#{CURL_BIN} -s -i -L -X DELETE"

    headers.each_pair { |k, v|
      cmdline += " -H '#{k}: #{v}'"
    }

    cmdline += " '#{url}#{self.build_params(params)}'"

    #log("DELETE: #{cmdline}");
    CurlResponse.build(`#{cmdline}`)
  end

  def self.postForm(url, form, headers = {})
    cmdline = "#{CURL_BIN} -s -i -L"

    headers.each_pair { |k, v|
      cmdline += " -H '#{k}: #{v}'"
    }

    form.each_pair { |k, v|
      if Array === v and Pathname === v[0]
        cmdline += " -F '#{URI.escape(k)}=@#{v[0].to_s}"

        cmdline += ";filename=#{v[1]}" if v.size > 1
        cmdline += ";type=#{v[2]}" if v.size > 2
        cmdline += "'"
      elsif Pathname === v
        cmdline += " -F '#{URI.escape(k)}=@#{v.to_s}'"
      else
        cmdline += " -F '#{URI.escape(k)}=#{URI.escape(v.to_s)}'"
      end
    }

    cmdline += " '#{url}'"

    #log("POST (form): #{cmdline}");
    CurlResponse.build(`#{cmdline}`)
  end

  def self.post(url, body = "", headers = {})
    cmdline = "#{CURL_BIN} -s -i -L"

    headers.each_pair { |k, v|
      cmdline += " -H '#{k}: #{v}'"
    }

    if Pathname === body
      cmdline += " -d @#{body.to_s}"
    else
      cmdline += " -d '#{body}'"
    end

    cmdline += " '#{url}'"

    #log("PUT: #{cmdline}");
    CurlResponse.build(`#{cmdline}`)
  end

  def self.put(url, body = "", headers = {})
    cmdline = "#{CURL_BIN} -s -i -L -X PUT"

    headers.each_pair { |k, v|
      cmdline += " -H '#{k}: #{v}'"
    }

    if Pathname === body
      cmdline += " -d @#{body.to_s}"
    else
      cmdline += " -d '#{body}'"
    end

    cmdline += " '#{url}'"

    #log("PUT: #{cmdline}");
    CurlResponse.build(`#{cmdline}`)
  end
end

class CouchDesign
  def self.eval_js(file, verbose = true)
    ofile = Tempfile.new("couchlint")
    #puts "temp: #{ofile.path}"

    begin
      ofile.write(JS_HEADER)
      ofile.write(File.open(file).read())
      #ofile.write(JS_FOOTER)

      #ofile.rewind
      #puts "--"
      #puts ofile.read()
      #puts "--"
      ofile.flush

      d = JS_HEADER.count("\n")
      IO.popen("#{Options.js} #{ofile.path} 2>&1") { |f|
        if verbose
          f.each_line() { |ln|
            #puts "line: #{ln}"
            m = /^([^:]+):([0-9]+):(.*)$/.match(ln)
            if m != nil
              lineno = m[2].to_i
              lineno -= d if lineno >= d
              src_error("#{file}:#{lineno}: #{m[3]}")
            else
              src_error("#{ln}") if ln.strip.size != 0
            end
          }
        end
      }

      if $? != nil && $?.exitstatus == 0
        ofile.write(JS_FOOTER)
        ofile.flush
        body = IO.popen("#{Options.js} #{ofile.path}") { |f|
          f.read()
        }
        return body
      else
        if DEBUG
          ofile.rewind
          puts "--"
          puts ofile.read()
          puts "--"
        end
      end

      nil

    ensure
      ofile.close
      ofile.unlink
    end
  end

  def initialize(name)
    resp = Curl.get("#{Options.url}/_design/#{URI.escape(name)}")
    jbody = JSON.parse(resp.body)

    if jbody["error"]
      @contents = {}
      @contents["language"] = "javascript"
      @contents["_id"] = "_design/#{name}"
    else
      @contents = jbody
    end
  end

  def id()
    @contents["_id"]
  end

  def rev(newRev = nil)
    @contents["_rev"] = newRev if newRev
    @contents["_rev"]
  end

  def name()
    File.basename(@contents["_id"])
  end

  def to_s()
    @contents
  end

  def to_json()
    @contents.to_json
  end

  def write(file)
    File.open(file, "w") { |f|
      f.write(@contents.to_json)
    }
  end

  def load(dir)
    load_shows(File.join(dir, "shows"))
    load_views(File.join(dir, "views"))

    Dir.glob(File.join(dir, "*.js")) { |func|
      next if ! File.file? func
      # e.g. func == "like/views/when/map.js"

      func_name = File.basename(func)
      func_name = func_name.chomp(File.extname(func_name))

      #puts "add util: #{func_name} = #{func}"
      body = CouchDesign.eval_js(func)
      if body
        @contents[func_name] = body

        verbose "  [#{func_name}] #{File.basename(func)}"
      end
    }

    # This call must be the last one
    register_attachments!(File.join(dir, "_attachments"))
  end

  def register_attachments!(att_dir)
    # THIS FUNCTION WILL DESTROY THE CONSISTENCE OF THE OBJECT!
    raise "design doc is not loaded" if ! @contents["_rev"]
    return if !File.directory? att_dir

    prefix_len = File.join(att_dir, "").size

    Dir.glob(File.join(att_dir, "**/*")) { |attfile|
      next if File.directory? attfile

      vpath = attfile[prefix_len..-1]

      types = MIME::Types::type_for(attfile)
      if types.size == 0
        resp = Curl.head("#{Options.url}/#{id}/#{vpath}")
        puts "attfile: #{attfile}"
        if resp.headers["Status"].to_i / 100 == 2
          mime = resp.headers["Content-Type"]
        else
          error "cannot determine MIME type for #{attfile}, ignored"
          next
        end
      else
        mime = types[0].to_s
      end

      #puts "posting #{vpath} (#{mime})"
      resp = Curl.postForm("#{Options.url}/#{id}",
                           { "_rev" => @contents["_rev"],
                             "_attachments" => [ Pathname.new(attfile),
                                                 vpath, mime ]},
                           { "Referer" => "#{Options.url}" })


      status = JSON.parse(resp.body)
      @contents["_rev"] = status["rev"]

      if status["error"]
        error("#{attfile}: #{status["error"]}: #{status["reason"]}")
      else
        verbose "  [attachment] #{vpath}"
      end
    }
  end

  def load_shows(shows_dir)
    return if !File.directory? shows_dir

    Dir.glob(File.join(shows_dir, "*.js")) { |func|
      # e.g. func == "like/views/when/map.js"
      next if ! File.file? func

      func_name = File.basename(func)
      func_name = func_name.chomp(File.extname(func_name))

      #puts "add show: #{func_name} = #{func}"
      add_show(func_name, func)
    }
  end

  def load_views(views_dir)
    return if !File.directory? views_dir

    Dir.glob(File.join(views_dir, "*")) { |view_dir|
      next if !File.directory? view_dir

      view_name = File.basename(view_dir)
      viewhash = {}
      Dir.glob(File.join(view_dir, "*.js")) { |func|
        # e.g. func == "like/views/when/map.js"
        next if ! File.file? func

        func_name = File.basename(func)
        func_name = func_name.chomp(File.extname(func_name))

        viewhash[func_name] = func
      }
      #puts "viewhash: #{viewhash}"
      add_view(view_name, viewhash)
    }
  end

  def add_show(name, show_file)
    body = CouchDesign.eval_js(show_file)
    if body
      @contents["shows"] = {} if !@contents["shows"]
      @contents["shows"][name] = body

      verbose "  [show] #{File.basename(show_file)}"
    end
  end

  def add_view(name, hash = {})
    # hash = { "map" => "map-pathname }
    yield hash if block_given?

    @contents["views"] = {} if !@contents["views"]

    hash.each_pair { |func, file|
      body = CouchDesign.eval_js(file)
      if body
        @contents["views"][name] = {} if !@contents["views"][name]
        @contents["views"][name][func] = body

        verbose "  [view] #{File.basename(file)}"
      end
    }
  end
end


class Options
  @@database = COUCH_URL
  @@verbose = false

  def self.which(cmd)
    # stealed from http://stackoverflow.com/questions/2108727
    exts = ENV['PATHEXT'] ? ENV['PATHEXT'].split(';') : ['']
    ENV['PATH'].split(File::PATH_SEPARATOR).each do |path|
      exts.each { |ext|
        exe = "#{path}/#{cmd}#{ext}"
        return exe if File.executable? exe
      }
    end
    return nil
  end

  @@jspath = self.which("js") or self.which("v8")

  def self.url()
    @@database
  end

  def self.js()
    @@jspath
  end

  def self.verbose()
    @@verbose
  end

  def self.parse!(args)
    opts = OptionParser.new { |opts|
      opts.banner = "Usage: #{PROGRAM_NAME} [OPTION...] DIRECTORY"
      opts.separator ""
      opts.on("-d", "--database [URL]",
           "CouchDB endpoint URL",
           "(default: \"#{COUCH_URL}\")") { |url|
        @@database = url
        @@database = @@database[0...-1] if @@database[-1] == "/"
      }

      opts.separator ""
      opts.on("-j", "--jspath [JS-PATH]",
           "Javascript interpreter") { |js|
        @@jspath = js
      }

      opts.on("-v", "--verbose",
           "Verbose output") {
        @@verbose = true
      }

      opts.separator ""

      opts.on("-h", "--help", "Show this message") {
        puts opts
        exit
      }
      opts.on("-V", "--version", "Show version and exit") {
        puts "#{PROGRAM_NAME} version #{VERSION}"
        exit
      }

      opts.separator ""
      opts.separator "Register design documents from DIRECTORY where it contains"
      opts.separator "files for the document."
      opts.separator ""

      opts.separator "  DIRECTORY/views/VIEW-NAME/*.js  (e.g. map.js or reduce.js)"
      opts.separator "  DIRECTORY/shows/*.js            (e.g. print.js or others)"
      opts.separator "  DIRECTORY/*.js                  (e.g. validate_doc_update.js)"
      opts.separator "  DIRCETORY/_attachments/*        (automatically uploaded)"
      opts.separator ""
      opts.separator "Report bugs to <cinsky@gmail.com> or post bugs to"
      opts.separator "  <https://github.com/cinsk/couch-register-design/issues>"
    }
    opts.parse!(args)

    if !File.executable?(@@jspath)
      error("#{@@jspath} is not an executable")
      exit 1
    end

  end
end

#puts "argv: #{ARGV}"
Options.parse!(ARGV)
#puts "argv: #{ARGV}"
#puts "url: #{Options.url}"

begin
  resp = Curl.put(Options.url)
rescue Exception => e
  error("#{e.message}\n")
  exit(1)
end

if ARGV.length < 1
  error("wrong number of argument(s)")
  error("Try \`-h' for more help.")
  exit 1
end

ARGV.each { |design_dir|
  verbose "Design: #{design_dir}"

  design_name = File.basename(design_dir)
  design = CouchDesign.new(design_name)
  design.load(design_dir)

  Tempfile.open("json") { |tmpfile|
    tmpfile.write(design.to_json)
    tmpfile.flush()

    resp = Curl.put("#{Options.url}/#{URI.escape(design.id)}",
                Pathname.new(tmpfile.path),
                { "Content-Type" => "application/json" })
    status = JSON.parse(resp.body)

    if DEBUG
      status.each_pair { |k, v|
        puts "PUT resp [#{k}] = [#{v}]"
      }
    end

    if status["error"]
      error("#{doc.id}: #{status["error"]}: #{status["reason"]}")
    else
      design.rev(status["rev"])
      verbose "  [revision] #{design.rev}"
    end
  }
}
