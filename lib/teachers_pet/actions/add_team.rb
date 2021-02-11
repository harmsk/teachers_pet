module TeachersPet
  module Actions
    class AddTeam < Base
      def read_info
        @organization = self.options[:organization]
        @repository = self.options[:repository]
        @team = self.options[:team]
        @permission = self.options[:permission]
      end

      def load_files
        @students = self.read_students_file
      end

      def run
        self.read_info
        self.init_client
        self.load_files

        org_hash = self.client.organization(@organization)
        abort('Organization could not be found') if org_hash.nil?
        puts "Found organization at: #{org_hash[:url]}"

        teams_by_name = self.client.existing_teams_by_name(@organization)
        team = teams_by_name[@team]
        abort "no such team: #{@team}" if team.nil?

        @students.keys.each do |student|
          repo_name = "#{student}-#{@repository}"

          unless self.client.repository?(@organization, repo_name)
            abort " ** ERROR ** - Can't find expected repository '#{repo_name}'"
          end

          repo = @organization + '/' + repo_name
          puts "adding team '#{@team}' to '#{repo}'"
          unless self.client.add_team_repository(team.id, repo, permission: @permission)
            abort " ** ERROR ** - Failed to add team to repository '#{repo}'"
          end
        end
      end
    end
  end
end
