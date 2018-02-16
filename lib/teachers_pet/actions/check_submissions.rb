require 'csv'

module TeachersPet
  module Actions
    class CheckSubmissions < Base

      def initialize(check_files, opts={})
        super(opts)
        @check_files = check_files
      end

      def read_info
        @repository = self.options[:repository]
        @organization = self.options[:organization]
        @deadline = Time.parse(self.options[:deadline])
        @report_filename = self.options[:report]

        @file_exists = self.options[:file_exists]
        unless @check_files.include? @file_exists then
          @check_files.push @file_exists
        end
        @check_files = @check_files.uniq
        if @check_files.empty? then
          @check_files.push '.'
        end
      end

      def load_files
        @students = self.read_students_file
      end

      def check_submissions
        self.init_client

        org_hash = self.client.organization(@organization)
        abort('Organization could not be found') if org_hash.nil?
        puts "Found organization at: #{org_hash[:url]}"

        # Load the teams - there should be one team per student.
        # Repositories are given permissions by teams
        org_teams = self.client.get_teams_by_name(@organization)

        # For each student - if an appropraite repository exists,
        # add it to the list.
        remotes = Array.new
        @students.keys.sort.each do |student|
          unless org_teams.key?(student)
            puts("  ** ERROR ** - no team for #{student}")
            next
          end
          repo_name = "#{student}-#{@repository}"

          unless self.client.repository?(@organization, repo_name)
            puts("  ** ERROR ** - no repository called #{repo_name}")
          end

          remotes.push student
        end

        @submissions = Hash.new
        remotes.each do |remote|
          submission = Hash.new
          @submissions[remote] = submission

          if self.options[:fetch] then
            system('git', 'remote', 'update', remote)
          end

          if @file_exists then
            submitted = system('git', 'cat-file', '-e', "#{remote}/master:#{@file_exists}", out: File::NULL, err: File::NULL)
          else
            # assume it was submitted if we aren't checking for a submission file.
            submitted = true
          end

          latest_change = nil
          if submitted then
            @check_files.each do |file|
              date = `git log -1 --format='%cI' '#{remote}/master' -- '#{file}'`.strip
              date = Time.parse(date) if date
              submission[file] = date

              if latest_change.nil? then
                latest_change = date
              end

              if date > latest_change then
                latest_change = date
              end
            end
          end
          submission[:submission_date] = latest_change

          days_late = nil
          if latest_change then
            diff = latest_change - @deadline
            days = diff / (60*60*24)
            if (days < 0) then
              days = 0
            else
              days = days.ceil
            end
            days_late = days
          end
          submission[:days_late] = days_late
        end
      end

      def write_report
        CSV.open(@report_filename, "wb") do |csv|
          csv << ['remote', 'submission_date', 'days_late']
          @submissions.each do |remote, submission|
            date = submission[:submission_date]
            date = date.strftime('%F %R') if date
            csv << [remote, date, submission[:days_late]]
          end
        end
      end

      def run
        self.read_info
        self.load_files

        self.check_submissions
        self.write_report
      end
    end
  end
end
