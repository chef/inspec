# copyright: 2015, Vulcano Security GmbH

require "shellwords" unless defined?(Shellwords)

module Inspec::Resources
  class Lines
    attr_reader :output

    def initialize(raw, desc)
      @output = raw
      @desc = desc
    end

    def lines
      output.split("\n").map(&:strip)
    end

    def to_s
      @desc
    end
  end

  class PostgresSession < Inspec.resource(1)
    name "postgres_session"
    supports platform: "unix"
    supports platform: "windows"
    desc "Use the postgres_session InSpec audit resource to test SQL commands run against a PostgreSQL database."
    example <<~EXAMPLE
      sql = postgres_session('username', 'password', 'host', 'port')
      query('sql_query', ['database_name'])` contains the query and (optional) database to execute

      # default values:
      # username: 'postgres'
      # port: '5432'
      # host: 'localhost'
      # db: databse == db_user running the sql query

      describe sql.query('SELECT * FROM pg_shadow WHERE passwd IS NULL;') do
        its('output') { should eq '' }
      end
    EXAMPLE

    def initialize(user, pass, host = nil, port = nil)
      @user = user || "postgres"
      @pass = pass
      @host = host || "localhost"
      @port = port || 5432
      raise Inspec::Exceptions::ResourceFailed, "Can't run PostgreSQL SQL checks without authentication." if @user.nil? || @pass.nil?

      test_connection
    end

    def query(query, db = [])
      raise Inspec::Exceptions::ResourceFailed, "#{resource_exception_message}" if resource_failed?

      psql_cmd = create_psql_cmd(query, db)
      cmd = inspec.command(psql_cmd, redact_regex: /(PGPASSWORD=').+(' psql .*)/)
      out = cmd.stdout + "\n" + cmd.stderr
      if cmd.exit_status != 0 || out =~ /could not connect to .*/ || out.downcase =~ /^error:.*/
        raise Inspec::Exceptions::ResourceFailed, "PostgreSQL query with errors: #{out}"
      else
        Lines.new(cmd.stdout.strip, "PostgreSQL query: #{query}")
      end
    end

    private

    def test_connection
      query("select now()")
    end

    def escaped_query(query)
      Shellwords.escape(query)
    end

    def create_psql_cmd(query, db = [])
      if inspec.platform.in_family?("windows")
        "psql -d postgresql://#{@user}:#{@pass}@#{@host}:#{@port}/#{db.first} -A -t -w -c \"#{query}\""
      else
        "psql -d postgresql://#{@user}:#{escaped_query(@pass)}@#{@host}:#{@port}/#{db.first} -A -t -w -c #{escaped_query(query)}"
      end
    end
  end
end
