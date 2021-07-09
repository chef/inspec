require "inspec/dist"

module InspecPlugins
  module Compliance
    class API
      module Login
        include Inspec::Dist

        class CannotDetermineServerType < StandardError; end

        def login(options)
          raise ArgumentError, "Please specify a server using `#{EXEC_NAME} automate login https://SERVER` or `#{EXEC_NAME} compliance login https://SERVER`" unless options["server"]

          options["server_type"] = "automate2"
          options["server"] = URI("https://#{options["server"]}").to_s if URI(options["server"]).scheme.nil?
          options["server"].delete_suffix!("/")

          Login::Automate2Server.login(options)
        end

        module Automate2Server
          def self.login(options)
            verify_thor_options(options)

            options["url"] = options["server"] + "/api/v0"
            token = options["dctoken"] || options["token"]
            success, msg = API::Login.authenticate_login(options)
            success ? store_access_token(options, token) : msg
          end

          def self.store_access_token(options, token)
            config = InspecPlugins::Compliance::Configuration.new
            config.clean

            config["automate"] = {}
            config["automate"]["ent"] = "automate"
            config["automate"]["token_type"] = "dctoken"
            config["server"] = options["url"]
            config["user"] = options["user"]
            config["owner"] = options["user"]
            config["insecure"] = options["insecure"] || false
            config["server_type"] = options["server_type"]
            config["token"] = token
            config["version"] = "0"

            config.store
            API::Login.configuration_stored_message(config)
          end

          def self.verify_thor_options(o)
            error_msg = []

            error_msg.push("Please specify a user using `--user='USER'`") if o["user"].nil?

            if o["token"].nil? && o["dctoken"].nil?
              error_msg.push("Please specify a token using `--token='APITOKEN'`")
            end

            raise ArgumentError, error_msg.join("\n") unless error_msg.empty?
          end
        end

        def self.authenticate_login(options)
          InspecPlugins::Compliance::API.authenticate_login_using_version_api(
            options["url"],
            options["token"],
            options["insecure"]
          )
        end

        def self.configuration_stored_message(config)
          "Stored configuration for Chef #{config["server_type"].capitalize}: #{config["server"]}' with user: '#{config["user"]}'"
        end
      end
    end
  end
end
