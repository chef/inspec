require "helper"
require "inspec/resource"
require "inspec/resources/http"
require "faraday_middleware/response/follow_redirects"

describe "Inspec::Resources::Http" do
  describe "InSpec::Resources::Http::Worker::Local" do
    let(:domain)      { "www.example.com" }
    let(:http_method) { "GET" }
    let(:opts)        { {} }
    let(:worker)      { Inspec::Resources::Http::Worker::Local.new(http_method, "http://#{domain}", opts) }

    describe "simple HTTP request with no options" do
      it "returns correct data" do
        stub_request(:get, domain).to_return(status: 200, body: "pong")

        _(worker.status).must_equal 200
        _(worker.body).must_equal "pong"
      end
    end

    describe "request with basic auth" do
      let(:opts) { { auth: { user: "user", pass: "pass" } } }

      it "returns correct data" do
        stub_request(:get, domain).with(basic_auth: %w{user pass}).to_return(status: 200, body: "auth ok")

        _(worker.status).must_equal 200
        _(worker.body).must_equal "auth ok"
      end
    end

    describe "request with redirect enabled" do
      let(:opts) { { max_redirects: 1 } }

      it "follows the redirect" do
        stub_request(:get, domain).to_return(status: 302, headers: { location: "http://example.com" } )
        stub_request(:get, "example.com").to_return(status: 200, body: "redirect ok")

        _(worker.status).must_equal 200
        _(worker.body).must_equal "redirect ok"
      end

      it "does not exceed max_redirects" do
        stub_request(:get, domain).to_return(status: 302, headers: { location: "http://redirect1.com" } )
        stub_request(:get, "redirect1.com").to_return(status: 302, headers: { location: "http://redirect2.com" } )
        stub_request(:get, "redirect2.com").to_return(status: 200, body: "should not get here")

        _(proc { worker.status }).must_raise FaradayMiddleware::RedirectLimitReached
      end
    end

    describe "POST request with data" do
      let(:http_method) { "POST" }
      let(:opts)        { { data: { a: "1", b: "five" } } }

      it "returns correct data" do
        stub_request(:post, domain).with(body: { a: "1", b: "five" }).to_return(status: 200, body: "post ok")

        _(worker.status).must_equal 200
        _(worker.body).must_equal "post ok"
      end
    end

    describe "with request headers" do
      let(:opts) { { headers: { "accept" => "application/json" } } }

      it "returns correct data" do
        stub_request(:get, domain).with(headers: { "accept" => "application/json" }).to_return(status: 200, body: "headers ok", headers: { "mock" => "ok" })

        _(worker.status).must_equal 200
        _(worker.body).must_equal "headers ok"
        _(worker.response_headers["mock"]).must_equal "ok"
      end
    end

    describe "with params" do
      let(:opts) { { params: { a: "b" } } }

      it "returns correct data" do
        stub_request(:get, domain).with(query: { a: "b" }).to_return(status: 200, body: "params ok")

        _(worker.status).must_equal 200
        _(worker.body).must_equal "params ok"
      end
    end

    describe "an OPTIONS request" do
      let(:http_method) { "OPTIONS" }
      let(:opts) do
        { headers: { "Access-Control-Request-Method" => "GET",
                     "Access-Control-Request-Headers" => "origin, x-requested-with",
                     "Origin" => "http://www.example.com" } }
      end

      it "returns correct data" do
        stub_request(:options, "http://www.example.com/")
          .with(headers: { "Access-Control-Request-Headers" => "origin, x-requested-with", "Access-Control-Request-Method" => "GET", "Origin" => "http://www.example.com" })
          .to_return(status: 200, body: "", headers: { "mock" => "ok", "Access-Control-Allow-Origin" => "http://www.example.com", "Access-Control-Allow-Methods" => "POST, GET, OPTIONS, DELETE", "Access-Control-Max-Age" => "86400" })

        _(worker.status).must_equal 200
        _(worker.response_headers["mock"]).must_equal "ok"
        _(worker.response_headers["access-control-allow-origin"]).must_equal "http://www.example.com"
        _(worker.response_headers["access-control-allow-methods"]).must_equal "POST, GET, OPTIONS, DELETE"
        _(worker.response_headers["access-control-max-age"]).must_equal "86400"
      end
    end
  end

  describe "Inspec::Resource::Http::Worker::Remote" do
    let(:backend)     { MockLoader.new.backend }
    let(:http_method) { "GET" }
    let(:url)         { "http://www.example.com" }
    let(:opts)        { {} }
    let(:worker)      { Inspec::Resources::Http::Worker::Remote.new(backend, http_method, url, opts) }

    describe "simple HTTP request with no options" do
      it "returns correct data" do
        _(worker.status).must_equal 200
        _(worker.body).must_equal "no options"
      end
    end

    describe "request with basic auth" do
      let(:opts) { { auth: { user: "user", pass: "pass" } } }

      it "returns correct data" do
        _(worker.status).must_equal 200
        _(worker.body).must_equal "auth ok"
      end
    end

    describe "request with redirect enabled" do
      let(:opts) { { max_redirects: 1 } }

      it "follows the redirect" do
        _(worker.status).must_equal 200
        _(worker.body).must_equal "followed redirect"
      end
    end

    describe "POST request with data" do
      let(:http_method) { "POST" }
      let(:opts)        { { data: { a: "1", b: "five" } } }

      it "returns correct data" do
        _(worker.status).must_equal 200
        _(worker.body).must_equal "post ok"
      end
    end

    describe "with request headers" do
      let(:opts) { { headers: { "accept" => "application/json", "foo" => "bar" } } }

      it "returns correct data" do
        _(worker.status).must_equal 200
        _(worker.body).must_equal "headers ok"
        _(worker.response_headers["mock"]).must_equal "ok"
      end
    end

    describe "with params" do
      let(:opts) { { params: { a: "b", c: "d" } } }

      it "returns correct data" do
        _(worker.status).must_equal 200
        _(worker.body).must_equal "params ok"
      end
    end

    describe "a HEAD request" do
      let(:http_method) { "HEAD" }

      it "returns correct data" do
        _(worker.status).must_equal 301
        _(worker.response_headers["Location"]).must_equal "http://www.google.com/"
      end
    end

    describe "an OPTIONS request" do
      let(:http_method) { "OPTIONS" }
      let(:opts) do
        { headers: { "Access-Control-Request-Method" => "GET",
                     "Access-Control-Request-Headers" => "origin, x-requested-with",
                     "Origin" => "http://www.example.com" } }
      end

      it "returns correct data" do
        _(worker.status).must_equal 200
        _(worker.response_headers["Access-Control-Allow-Origin"]).must_equal "http://www.example.com"
        _(worker.response_headers["Access-Control-Allow-Methods"]).must_equal "POST, GET, OPTIONS, DELETE"
        _(worker.response_headers["Access-Control-Max-Age"]).must_equal "86400"
      end
    end

    describe "run_http request" do
      it "returns nil when nil is returned" do
        Inspec::Resources::Cmd.any_instance
          .stubs(:stdout)
          .returns(nil)
        _(worker.send(:run_http)).must_be_nil
      end

      it "returns nil when failure is returned" do
        Inspec::Resources::Cmd.any_instance
          .stubs(:exit_status)
          .returns(1)
        _(worker.send(:run_http)).must_be_nil
      end

      it "returns html when html is returned" do
        Inspec::Resources::Cmd.any_instance
          .stubs(:stdout)
          .returns("HTTP/1.1 200 OK\nDate: Tue, 03 Oct 2017 20:30:08 GMT\nExpires: -1\nCache-Control: private")
        assert = ["Date: Tue, 03 Oct 2017 20:30:08 GMT", "Expires: -1", "Cache-Control: private"]
        _(worker.send(:run_http)).must_equal assert
      end
    end
  end

  describe "Inspec::Resource::Http::Headers" do
    let(:headers) { Inspec::Resources::Http::Headers.create(a: 1, B: 2, "c" => 3, "D" => 4) }

    it "returns the correct data via hash syntax ensuring case-insensitive keys" do
      _(headers["a"]).must_equal(1)
      _(headers["A"]).must_equal(1)
      _(headers["b"]).must_equal(2)
      _(headers["B"]).must_equal(2)
      _(headers["c"]).must_equal(3)
      _(headers["C"]).must_equal(3)
      _(headers["d"]).must_equal(4)
      _(headers["D"]).must_equal(4)
    end

    it "returns the correct data via method syntax ensuring case-insensitive keys" do
      _(headers.a).must_equal(1)
      _(headers.A).must_equal(1)
      _(headers.b).must_equal(2)
      _(headers.B).must_equal(2)
      _(headers.c).must_equal(3)
      _(headers.C).must_equal(3)
      _(headers.d).must_equal(4)
      _(headers.D).must_equal(4)
    end
  end

  describe "Windows-Simple" do
    let(:backend)     { MockLoader.new(:windows).backend }
    let(:http_method) { "GET" }
    let(:url)         { "https://www.example.com" }
    let(:opts)        { {} }
    let(:worker)      { Inspec::Resources::Http::Worker::Remote.new(backend, http_method, url, opts) }

    describe "simple HTTP request with no options" do
      it "returns correct data" do
        Inspec::Resources::Cmd.any_instance
          .stubs(:exist?)
          .returns(true)
        _(worker.status).must_equal 200
        _(worker.response_headers["Content-Type"]).must_equal "text/html; charset=UTF-8"
      end
    end
  end

  describe "Windows-Head" do
    let(:backend)     { MockLoader.new(:windows).backend }
    let(:http_method) { "HEAD" }
    let(:url)         { "https://www.example.com" }
    let(:opts)        { {} }
    let(:worker)      { Inspec::Resources::Http::Worker::Remote.new(backend, http_method, url, opts) }

    describe "simple Head request" do
      it "returns correct data" do
        Inspec::Resources::Cmd.any_instance
          .stubs(:exist?)
          .returns(true)
        _(worker.status).must_equal 200
        _(worker.response_headers["Content-Type"]).must_equal "text/html; charset=UTF-8"
      end
    end
  end
end
