module TeachersPet
  module Actions
    class PushFiles < Base
      def read_info
        @repository = self.options[:repository]
        @organization = self.options[:organization]
        @branch = self.options[:branch]
        @disable_force_push = self.options[:disable_force_push]
        @sshEndpoint = self.options[:ssh]
      end

      def load_files
        @students = self.read_students_file
      end

      def push
        self.init_client

        org_hash = self.client.organization(@organization)
        abort('Organization could not be found') if org_hash.nil?
        puts "Found organization at: #{org_hash[:url]}"

        # Load the teams - there should be one team per student.
        # Repositories are given permissions by teams
        org_teams = self.client.get_teams_by_name(@organization)

        # For each student - if an appropraite repository exists,
        # add it to the list.
        remotes_to_add = Hash.new
        repositories = Hash.new
        @students.keys.sort.each do |student|
          unless org_teams.key?(student)
            puts("  ** ERROR ** - no team for #{student}")
            next
          end
          repo_name = "#{student}-#{@repository}"

          unless self.client.repository?(@organization, repo_name)
            puts("  ** ERROR ** - no repository called #{repo_name}")
          else
            repositories[student] = "#{@organization}/#{repo_name}"
          end

          if TeachersPet::Configuration.remoteSsh
            remotes_to_add[student] = "git@#{@sshEndpoint}:#{@organization}/#{repo_name}.git"
          else
            remotes_to_add[student] = "#{self.web}#{@organization}/#{repo_name}.git"
          end
        end

        puts "Adding remotes and pushing files to student repositories."
        remotes_to_add.keys.each do |remote|
          puts "#{remote} --> #{remotes_to_add[remote]}"
          if system('git', 'remote', 'add', remote, remotes_to_add[remote]) then
            system('git', 'config', '--add', "remote.#{remote}.fetch", "+refs/tags/*:refs/tags/remotes/#{remote}/*")
          end
          system('git', 'push', remote, @branch)

          unless @disable_force_push.nil? then
            puts " --> disabling force push #{repositories[remote]}/#{@branch}"
            self.client.protect_branch(repositories[remote], @branch,
              required_status_checks: { strict: @disable_force_push, contexts: []},
              enforce_admins: false,
              required_pull_request_reviews: nil,
              # TODO: using preview API
              accept: 'application/vnd.github.luke-cage-preview+json'
            )
          end
        end
      end

      def run
        self.read_info
        self.load_files
        self.push
      end
    end
  end
end
