require 'active_support/core_ext/hash/keys'
require 'io/console'
require 'octokit'
require_relative File.join('..', 'configuration')

module TeachersPet
  module Actions
    class Base
      attr_reader :client, :options

      def initialize(opts={})
        @options = opts.symbolize_keys
      end

      def octokit_config
        opts = {
          api_endpoint: self.options[:api],
          web_endpoint: self.options[:web],
          login: self.options[:username],
          # Organizations can get big, pull in all pages
          auto_paginate: true
        }

        if self.options[:token]
          if self.options[:token].eql?('token')
            print 'Please enter your GitHub token: '
            opts[:access_token] = STDIN.noecho(&:gets).chomp
          else
            opts[:access_token] = self.options[:token]
          end
        elsif self.options[:password]
          if self.options[:password].eql?('password')
            print 'Please enter your GitHub password: '
            opts[:password] = STDIN.noecho(&:gets).chomp
          else
            opts[:password] = self.options[:password]
          end
        else
          raise Thor::RequiredArgumentMissingError.new("No value provided for option --password or --token")
        end

        opts
      end

      def init_client
        puts "=" * 50
        puts "Authenticating to GitHub..."
        octokit = Octokit::Client.new(self.octokit_config)
        @client = TeachersPet::ClientDecorator.new(octokit)
      end

      def read_file(filename)
        map = Hash.new
        File.open(filename).each_line do |team|
          # Team can be a single user, or a team name and multiple users
          # Trim whitespace, otherwise issues occur
          team.strip!
          items = team.split(' ')
          items.each do |item|
            abort("No users can be named 'owners' (in any case)") if 'owners'.eql?(item.downcase)
          end

          # If this is a user, is the username valid?
          name = items[0]
          if (items.size == 1)
            user = validate_user(name)
          end

          if map[name].nil?
            puts " -> #{name}"

            if (items.size > 1)
              map[name] = Array.new
              print "  \\-> members: "
              1.upto(items.size - 1) do |i|
                current = items[i]
                user = validate_user(current)
                if user
                  print "#{items[i]} "
                  map[name] << items[i]
                else
                  $stderr.puts "    \\ -> warning: no such user, #{current}. skipping."
                end
              end
              print "\n"
            else
              if user
                map[name] = [user[:login]]
              else
                $stderr.puts "  \\ -> warning: no such user, #{name}. skipping."
              end
            end
          else
            $stderr.puts " \\ -> warning: ignoring duplicate user/team, #{name}. skipping."
          end
        end

        map
      end

      def validate_user(username)
        self.client.user(username)
      rescue Octokit::NotFound
        nil
      end

      def read_students_file
        student_file = self.options[:students]
        puts "Loading students:"
        students = read_file(student_file)

        excluded_file = self.options[:exclude_students]
        if excluded_file then
          puts "Loading excluded students:"
          excluded = read_file(excluded_file)
          excluded.keys.each do |key|
            students.delete(key)
          end
        end

        students
      end

      def read_members_file
        file = self.options[:members]
        puts "Loading members to add:"
        read_file(file).keys
      end

      def execute(command)
        return system(command)
      end
    end
  end
end
