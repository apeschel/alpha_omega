require 'capistrano/gateway'
require 'capistrano/ssh'

module Capistrano
  class Configuration
    module Connections
      def self.included(base)
        base.send :alias_method, :initialize_without_connections, :initialize
        base.send :alias_method, :initialize, :initialize_with_connections
      end

      # An adaptor for making the SSH interface look and act like that of the
      # Gateway class.
      class DefaultConnectionFactory #:nodoc:
        def initialize(options)
          @options = options
        end

        def connect_to(server)
          SSH.connect(server, @options)
        end
      end

      # A hash of the SSH sessions that are currently open and available.
      # Because sessions are constructed lazily, this will only contain
      # connections to those servers that have been the targets of one or more
      # executed tasks.
      attr_reader :sessions

      def initialize_with_connections #:nodoc:
        initialize_without_connections
        @sessions = {}
      end

      # Used to force connections to be made to the current task's servers.
      # Connections are normally made lazily in Capistrano--you can use this
      # to force them open before performing some operation that might be
      # time-sensitive.
      def connect!(options={})
        execute_on_servers(options) { }
      end

      # Returns the object responsible for establishing new SSH connections.
      # The factory will respond to #connect_to, which can be used to
      # establish connections to servers defined via ServerDefinition objects.
      def connection_factory
        @connection_factory ||= begin
          options = { :user => fetch(:user, nil),
            :password => fetch(:password, nil),
            :port => fetch(:port, nil),
            :ssh_options => fetch(:ssh_options, nil) }

          if exists?(:gateway)
            logger.debug "establishing connection to gateway `#{fetch(:gateway)}'"
            Gateway.new(ServerDefinition.new(fetch(:gateway)), options)
          else
            DefaultConnectionFactory.new(options)
          end
        end
      end

      # Ensures that there are active sessions for each server in the list.
      def establish_connections_to(servers)
        servers = Array(servers)

        # because Net::SSH uses lazy loading for things, we need to make sure
        # that at least one connection has been made successfully, to kind of
        # "prime the pump", before we go gung-ho and do mass connection in
        # parallel. Otherwise, the threads start doing things in wierd orders
        # and causing Net::SSH to die of confusion.
        # TODO investigate Net::SSH and see if this can't be solved there

        if sessions.empty?
          server, servers = servers.first, servers[1..-1]
          sessions[server.host] = connection_factory.connect_to(server)
        end

        servers.map { |server| establish_connection_to(server) }.each { |t| t.join }
      end

      # Determines the set of servers within the current task's scope and
      # establishes connections to them, and then yields that list of
      # servers.
      def execute_on_servers(options={})
        raise ArgumentError, "expected a block" unless block_given?

        task = current_task
        raise ScriptError, "there is no active task" if task.nil?

        servers = task.servers

        if servers.empty?
          raise ScriptError, "`#{task.fully_qualified_name}' is only run for servers matching #{task.options.inspect}, but no servers matched"
        end

        servers = [servers.first] if options[:once]
        logger.trace "servers: #{servers.map { |s| s.host }.inspect}"

        # establish connections to those servers, as necessary
        establish_connections_to(servers)
        yield servers
      end

      private

        # We establish the connection by creating a thread in a new method--this
        # prevents problems with the thread's scope seeing the wrong 'server'
        # variable if the thread just happens to take too long to start up.
        def establish_connection_to(server)
          Thread.new { sessions[server.host] ||= connection_factory.connect_to(server) }
        end
    end
  end
end