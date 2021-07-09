# copyright: 2017, Criteo
# copyright: 2017, Chef Software Inc
# license: Apache v2

require "inspec/resources/command"
require "faraday" unless defined?(Faraday)
require "faraday_middleware"
require "hashie"

module Inspec::Resources
  class Http < Inspec.resource(1)
    name "http"
    supports platform: "unix"
    supports platform: "windows"
    desc "Use the http InSpec audit resource to test http call."
    example <<~EXAMPLE
      describe http('http://localhost:8080/ping', auth: {user: 'user', pass: 'test'}, params: {format: 'html'}) do
        its('status') { should cmp 200 }
        its('body') { should cmp 'pong' }
        its('headers.Content-Type') { should cmp 'text/html' }
      end

      describe http('http://example.com/ping').headers do
        its('Content-Length') { should cmp 258 }
        its('Content-Type') { should cmp 'text/html; charset=UTF-8' }
      end
    EXAMPLE

    def initialize(url, opts = {})
      @url = url
      @opts = opts

      # Prior to InSpec 2.0 the HTTP test had to be instructed to run on the
      # remote target machine. This warning will be removed after a few months
      # to give users an opportunity to remove the unused option from their
      # profiles.
      if opts.key?(:enable_remote_worker) && !inspec.local_transport?
        warn "Ignoring `enable_remote_worker` option, the `http` resource ",
             "remote worker is enabled by default for remote targets and ",
             "cannot be disabled"
      end

      # Run locally if InSpec is ran locally and remotely if ran remotely
      if inspec.local_transport?
        @worker = Worker::Local.new(http_method, url, opts)
      else
        @worker = Worker::Remote.new(inspec, http_method, url, opts)
      end
    end

    def status
      @worker.status
    end

    def headers
      @headers ||= Inspec::Resources::Http::Headers.create(@worker.response_headers)
    end

    def body
      @worker.body&.force_encoding(Encoding::UTF_8)
    end

    def http_method
      @opts.fetch(:method, "GET")
    end

    def to_s
      if @opts && @url
        "HTTP #{http_method} on #{@url}"
      else
        "HTTP Resource"
      end
    end

    class Worker
      class Base
        attr_reader :http_method, :opts, :url

        def initialize(http_method, url, opts)
          @http_method = http_method
          @url = url
          @opts = opts
          @response = nil
        end

        private

        def params
          opts.fetch(:params, nil)
        end

        def username
          opts.fetch(:auth, {})[:user]
        end

        def password
          opts.fetch(:auth, {})[:pass]
        end

        def request_headers
          opts.fetch(:headers, {})
        end

        def request_body
          opts[:data]
        end

        # not supported on Windows
        def open_timeout
          opts.fetch(:open_timeout, 60)
        end

        def read_timeout
          opts.fetch(:read_timeout, 60)
        end

        def ssl_verify?
          opts.fetch(:ssl_verify, true)
        end

        def max_redirects
          opts.fetch(:max_redirects, nil)
        end
      end

      class Local < Base
        def status
          response.status
        end

        def body
          response.body
        end

        def response_headers
          response.headers.to_h
        end

        private

        def response
          return @response if @response

          conn = Faraday.new(url: url, headers: request_headers, params: params, ssl: { verify: ssl_verify? }) do |builder|
            builder.request :url_encoded
            builder.use FaradayMiddleware::FollowRedirects, limit: max_redirects unless max_redirects.nil?
            builder.adapter Faraday.default_adapter
          end

          # set basic authentication
          conn.basic_auth username, password unless username.nil? || password.nil?

          # set default timeout
          conn.options.timeout      = read_timeout  # open/read timeout in seconds
          conn.options.open_timeout = open_timeout  # connection open timeout in seconds

          @response = conn.run_request(http_method.downcase.to_sym, nil, nil, nil) do |req|
            req.body = request_body
          end
        end
      end

      class Remote < Base
        attr_reader :inspec

        def initialize(inspec, http_method, url, opts)
          http_cmd = inspec.os.windows? ? "Invoke-WebRequest" : "curl"
          unless inspec.command(http_cmd).exist?
            raise Inspec::Exceptions::ResourceSkipped,
                  "#{http_cmd} is not available on the target machine"
          end
          @ran_http = false
          @inspec = inspec
          super(http_method, url, opts)
        end

        def status
          run_http
          @status
        end

        def body
          run_http
          @body&.strip
        end

        def response_headers
          run_http
          @response_headers
        end

        private

        def run_http
          return if @ran_http

          cmd_result = inspec.command(http_command)
          response = cmd_result.stdout
          @ran_http = true
          return if response.nil? || cmd_result.exit_status != 0

          if inspec.os.windows?
            response = JSON.parse(response)
            @status = response["StatusCode"]
            @body = response["RawContent"]

            @response_headers = {}
            response["Headers"].each do |name, value|
              @response_headers["#{name}"] = value
            end
          else
            # strip any carriage returns to normalize output
            response.delete!("\r")

            # split the prelude (status line and headers) and the body
            prelude, remainder = response.split("\n\n", 2)
            loop do
              break unless remainder =~ %r{^HTTP/}

              prelude, remainder = remainder.split("\n\n", 2)
            end
            @body = remainder
            prelude = prelude.lines

            # grab the status off of the first line of the prelude
            status_line = prelude.shift
            @status = status_line.split(" ", 3)[1].to_i

            # parse the rest of the prelude which will be all the HTTP headers
            @response_headers = {}
            prelude.each do |line|
              line.strip!
              key, value = line.split(":", 2)
              @response_headers[key] = value.strip
            end

          end
        end

        def http_command # rubocop:disable Metrics/AbcSize
          if inspec.os.windows?
            cmd = ["Invoke-WebRequest"]

            cmd << "-Method #{http_method}"
            # Missing connect-timeout
            cmd << "-TimeoutSec #{open_timeout + read_timeout}"
            # Insecure not supported simply https://stackoverflow.com/questions/11696944/powershell-v3-invoke-webrequest-https-error
            cmd << "-Body #{request_body.gsub('"', '`"')}" unless request_body.nil?
            cmd << "-MaximumRedirection #{max_redirects}" unless max_redirects.nil?
            request_headers["Authorization"] = """ '\"Basic ' + [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(\"#{username}:#{password}\")) +'\"' """ unless username.nil? || password.nil?

            request_header_string = nil
            request_headers.each do |k, v|
              request_header_string << " #{k} = #{v}"
            end
            cmd << "-Headers @{#{request_header_string.join(";")}}" unless request_header_string.nil?
            if params.nil?
              cmd << "'#{url}'"
            else
              cmd << "'#{url}?#{params.map { |e| e.join("=") }.join("&")}'"
            end
            cmd << "| Select-Object -Property * | ConvertTo-json" # We use `Select-Object -Property * ` to get around an odd PowerShell error
            cmd.join(" ")
          else
            cmd = ["curl -i"]

            # Use curl's --head option when the method requested is HEAD. Otherwise,
            # the user may experience a timeout when curl does not properly close
            # the connection after the response is received.
            if http_method.casecmp("HEAD") == 0
              cmd << "--head"
            else
              cmd << "-X #{http_method}"
            end

            cmd << "--connect-timeout #{open_timeout}"
            cmd << "--max-time #{open_timeout + read_timeout}"
            cmd << "--user \'#{username}:#{password}\'" unless username.nil? || password.nil?
            cmd << "--insecure" unless ssl_verify?
            cmd << "--data #{Shellwords.shellescape(request_body)}" unless request_body.nil?
            cmd << "--location" unless max_redirects.nil?
            cmd << "--max-redirs #{max_redirects}" unless max_redirects.nil?

            request_headers.each do |k, v|
              cmd << "-H '#{k}: #{v}'"
            end

            if params.nil?
              cmd << "'#{url}'"
            else
              cmd << "'#{url}?#{params.map { |e| e.join("=") }.join("&")}'"
            end

            cmd.join(" ")
          end
        end
      end
    end

    class Headers < Hash
      def self.create(header_data)
        header_data.each_with_object(new) { |(k, v), memo| memo[k.to_s.downcase] = v }
      end

      def [](requested_key)
        fetch(requested_key.downcase, nil)
      end

      def method_missing(requested_key)
        fetch(requested_key.to_s.downcase, nil)
      end
    end
  end
end
