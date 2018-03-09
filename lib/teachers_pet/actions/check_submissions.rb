require 'csv'

module TeachersPet
  module Actions
    class CheckSubmissions < Base

      def initialize(check_files, opts={})
        super(opts)
        @check_files = check_files

        @students = self.read_students_file

        @repository = self.options[:repository]
        @organization = self.options[:organization]
        @deadline = Time.parse(self.options[:deadline])
        @report_filename = self.options[:report]

        @validate_teams = self.options[:team_validation]

        @submit_file = self.options[:submit_file]
        unless @check_files.include? @submit_file then
          @check_files.push @submit_file
        end
        @check_files = @check_files.uniq
        if @check_files.empty? then
          @check_files.push '.'
        end

        @ignore_commit = self.options[:ignore_commit]
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
          if @validate_teams
            unless org_teams.key?(student)
              puts("  ** ERROR ** - no team for #{student}")
              next
            end
            repo_name = "#{student}-#{@repository}"

            unless self.client.repository?(@organization, repo_name)
              puts("  ** ERROR ** - no repository called #{repo_name}")
            end
          end
          remotes.push student
        end

        @submissions = Hash.new
        remotes.each do |remote|
          submission = Hash.new
          @submissions[remote] = submission
          repo_name = "#{@organization}/#{remote}-#{@repository}"

          # Fetch the latest changes
          if self.options[:fetch] then
            system('git', 'remote', 'update', remote)
          end

          # Check if the submission file exists
          if @submit_file then
            submitted = system('git', 'cat-file', '-e', "#{remote}/master:#{@submit_file}", out: File::NULL, err: File::NULL)
            submission[:submitted] = submitted
          end

          # Check if there were commits for required submission files
          latest = Hash.new
          @check_files.each do |file|
            date_commit = `git log -1 --format='%cI\n%H' '#{remote}/master' -- '#{file}'`.strip
            date = date_commit.lines.first
            commit = date_commit.lines.last

            next if date.nil?
            date = Time.parse(date)
            next if commit.nil?

            # Do not count this submission, it it's part of the ignore commits
            next if commit == @ignore_commit

            if latest[:date].nil? then
              latest[:date] = date
              latest[:commit] = commit
            elsif date > latest[:date] then
              latest[:date] = date
              latest[:commit] = commit
            end
          end
          submission[:commit] = latest[:commit]
          submission[:committed_at] = latest[:date]

          # Check for push events for timely submission
          # Students may push after the deadline and claim it was one time.
          if latest[:commit] then
            # If we can't find a commit, then there's no point looking for a push.

            events =  self.client.repository_events(repo_name)
            found_commit_push = false
            events.each do |event|
              event = event.to_hash
              if event[:type] == "PushEvent" then
                before = event[:payload][:before]
                head = event[:payload][:head]

                commits = `git log --format='%H' #{before}..#{head} 2>&1`.strip
                if $?.success?
                  commits.each_line do |commit|
                    commit = commit.strip
                    if latest[:commit] == commit then
                      found_commit_push = true;
                      break
                    end
                  end
                else
                  # looks like the student modified the history...
                  submission[:rewrite_history] = commits

                  # let's try to find the commit in what GitHub gives us...
                  commits = event[:payload][:commits]
                  commits.each do |commit|
                    commit = commit.to_hash
                    if commit[:sha] == latest[:commit] then
                      found_commit_push = true;
                      break
                    end
                  end
                end

                if found_commit_push then
                  push_time = event[:created_at].localtime
                  submission[:pushed_at] = push_time
                  break
                end
              end
            end
          end

          submission[:slip_days] = slip_days(submission[:committed_at], submission[:pushed_at])
        end

        # If we fetched, compress the repo
        if self.options[:fetch] then
          system('nice', 'git', 'gc')
        end
      end

      def slip_days(committed_at, pushed_at)
        days_late = nil

        if committed_at and !pushed_at then
          raise "no push date"
        elsif pushed_at
          diff = pushed_at - @deadline
          days = diff / (60*60*24)
          if (days < 0) then
            days = 0
          else
            days = days.ceil
          end
          days_late = days
        end
        days_late
      end

      def write_report
        CSV.open(@report_filename, "wb") do |csv|
          csv << ['remote', 'submitted', 'commit', 'committed_at', 'pushed_at', 'slip_days', 'rewrite_history']
          @submissions.each do |remote, submission|
            date = submission[:committed_at]
            date = date.strftime('%F %T') if date
            push = submission[:pushed_at]
            push = push.strftime('%F %T') if push
            csv << [remote, submission[:submitted].to_s.upcase, submission[:commit], date, push, submission[:slip_days], submission[:rewrite_history]]
          end
        end
      end

      def run
        self.check_submissions
        self.write_report
      end
    end
  end
end
