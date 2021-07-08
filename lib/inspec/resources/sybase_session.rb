require "inspec/resources/command"
require "inspec/utils/database_helpers"
require "hashie/mash"
require "csv" unless defined?(CSV)
require "tempfile" unless defined?(Tempfile)

module Inspec::Resources
  # STABILITY: Experimental
  # This resource needs further testing and refinement
  #
  class SybaseSession < Inspec.resource(1)
    name "sybase_session"
    supports platform: "unix"
    # supports platform: "windows" # TODO
    desc "Use the sybase_session InSpec resource to test commands against an Sybase database"
    example <<~EXAMPLE
      sql = sybase_session(username: 'my_user', password: 'password', server: 'SYBASE', database: 'pubs2')
      describe sql.query(\"SELECT * FROM authors\").row(0).column('au_lname') do
        its('value') { should eq 'Smith' }
      end
    EXAMPLE

    # TODO: allow to set -I interfaces file
    # TODO: allow to customize -s column separator
    attr_reader :bin, :col_sep, :database, :password, :server, :sybase_home, :username

    def initialize(opts = {})
      @username = opts[:username]
      @password = opts[:password]
      @database = opts[:database]
      @server = opts[:server]
      @sybase_home = opts[:sybase_home] || "/opt/sap"
      @bin = opts[:bin] || "isql"
      @col_sep = "|"

      fail_resource "Can't run Sybase checks without authentication" unless username && password
      fail_resource "You must provide a server name for the session" unless server
      fail_resource "You must provide a database name for the session" unless database
      fail_resource "Cannot find #{bin} CLI tool" unless inspec.command(bin).exist?
    end

    def query(sql)
      # We must write the SQl to a temp file on the remote target
      # try to get a temp path
      sql_file_path = upload_sql_file(sql)

      # isql reuires that we have a matching locale set, but does not support C.UTF-8. en_US.UTF-8 is the least evil.
      command = "LANG=en_US.UTF-8 SYBASE=#{sybase_home} #{bin} -s\"#{col_sep}\" -w80000 -S #{server} -U #{username} -D #{database} -P \"#{password}\" < #{sql_file_path}"
      isql_cmd = inspec.command(command)

      # Check for isql errors
      res = isql_cmd.exit_status
      raise Inspec::Exceptions::ResourceFailed.new("isql exited with code #{res} and stderr '#{isql_cmd.stderr}', stdout '#{isql_cmd.stdout}'") unless res == 0
      # isql is ill-behaved, and returns 0 on error
      raise Inspec::Exceptions::ResourceFailed.new("isql exited with error '#{isql_cmd.stderr}', stdout '#{isql_cmd.stdout}'") unless isql_cmd.stderr == ""
      # check stdout for error messages when stderr is empty "Msg 102, Level 15, State 181:\nServer 'SYBASE', Line 1:\nIncorrect syntax near '.'.\n"
      raise Inspec::Exceptions::ResourceFailed.new("isql exited with error #{isql_cmd.stdout}") if isql_cmd.stdout.match?(/Msg\s\d+,\sLevel\s\d+,\sState\s\d+/)

      # Clean up temporary file
      rm_cmd = inspec.command("rm #{sql_file_path}")
      res = rm_cmd.exit_status # TODO: handle
      raise Inspec::Exceptions::ResourceFailed.new("Unable to delete temproary SQL input file at #{sql_file_path}: #{rm_cmd.stderr}") unless res == 0

      DatabaseHelper::SQLQueryResult.new(isql_cmd, parse_csv_result(isql_cmd.stdout))
    end

    def to_s
      "Sybase Session"
    end

    private

    def parse_csv_result(stdout)
      output = stdout.gsub(/\r/, "").strip
      lines = output.lines
      # Remove second row (all dashes) and last 2 rows (blank and summary lines)
      trimmed_output = ([lines[0]] << lines.slice(2..-3)).join("")
      header_converter = Proc.new do |header|
        # This is here to suppress a warning from Hashie::Mash when it encounters a
        # header column that ends up with the name "default", which happens when using the
        # sybase_conf resource. It does mean that aly query whose output field includes the name
        # Default (exactly) will get renamed to default_value, but that seems unlikely.
        if header.match?(/^Default\s+$/)
          "default_value"
        else
          header.downcase.strip
        end
      end
      field_converter = ->(field) { field&.strip }
      CSV.parse(trimmed_output, headers: true, header_converters: header_converter, converters: field_converter, col_sep: col_sep).map { |row| Hashie::Mash.new(row.to_h) }
    end

    def upload_sql_file(sql)
      remote_temp_dir = "/tmp"
      remote_file_path = nil
      local_temp_file = Tempfile.new(["sybase", ".sql"])
      begin
        local_temp_file.write("#{sql}\n")
        local_temp_file.write("go\n")
        local_temp_file.flush
        filename = File.basename(local_temp_file.path)
        remote_file_path = "#{remote_temp_dir}/#{filename}"
        inspec.backend.upload([local_temp_file.path], remote_temp_dir)
      ensure
        local_temp_file.close
        local_temp_file.unlink
      end
      remote_file_path
    end
  end
end
