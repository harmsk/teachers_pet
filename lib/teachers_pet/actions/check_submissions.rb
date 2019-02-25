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
        @submit_tag = self.options[:submit_tag]
        @check_submit = (@submit_file or @submit_tag)

        # load module to check submit file
        @submit_file_plugin = self.options[:submit_file_plugin]
        if @submit_file_plugin then
          abort("submit-file required for plugin use.") unless @submit_file

          @submit_file_plugin = File.absolute_path(@submit_file_plugin)
          require_relative File.join('..', 'submit_file')
          require @submit_file_plugin

          @submit_file_plugins = []
          TeachersPet::SubmitFile.descendants.each do |c|
            @submit_file_plugins.push c.new
          end
          abort("failed to load plugin") if @submit_file_plugins.empty?
        end

        if @submit_file and !(@check_files.include? @submit_file) then
          @check_files.push @submit_file
        end
        @check_files = @check_files.uniq
        if @check_files.empty? then
          @check_files.push '.'
        end

        @tag_submission = self.options[:push_submission_tag]

        @ignored_commits = self.options[:ignore_commits]
        @ignored_commits = Array.new if @ignored_commits.nil?
        @ignored_students = self.options[:ignore_students]
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
          if @ignore_students then
            next if @ignore_students.include? student
          end

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
          remote_ref = "#{remote}/master"
          submit_tag = "remotes/#{remote}/#{@tag_submission}"

          # Fetch the latest changes
          # TODO: fetch automatically if using submit_tag
          if self.options[:fetch] then
            # Get the hash of the submission tag
            if @tag_submission then
              unless `git tag -l #{submit_tag}`.strip.empty? then
                submit_tag_hash = `git log -1 --format='%H' '#{submit_tag}' --`.strip
              end
            end
            system('git', 'fetch', '--no-tags', '--prune', remote)

            # Check if the student tried to change the submission tag
            if submit_tag_hash then
              hash_check = `git log -1 --format='%H' '#{submit_tag}' -- 2>/dev/null`.strip
              if submit_tag_hash != hash_check then
                submit_tag_hash = hash_check
                submission[:rewrite_history] = "WARNING: #{remote} #{@tag_submission} changed #{submit_tag_hash} => #{hash_check}"
              end
            end
          end

          # Check if the submission file exists
          if @submit_file then
            submitted = system('git', 'cat-file', '-e', "#{remote_ref}:#{@submit_file}", out: File::NULL, err: File::NULL)
            if submitted then
              submit_hash = `git log -1 --format='%H' '#{remote_ref}' -- '#{@submit_file}'`.strip
              if @ignored_commits.include? submit_hash then
                submitted = false
              elsif !@submit_file_plugins.empty?
                submit_file_contents = `git show '#{remote_ref}':'#{@submit_file}'`.strip
                @submit_file_plugins.each do |plugin|
                  submitted &&= plugin.verify submit_file_contents
                end
                submission[:submitted] = submitted
              else
                submission[:submitted] = submitted
              end
            end
          end

          # Check if the submission tag exists
          if @submit_tag then
            # TODO: build support for submit tag
            raise "TODO: not yet implemented."
          end

          # Check if there were commits for required submission files
          latest = Hash.new
          if submit_tag_hash then
            # we have a submission tag, use that for the commits
            unless @ignored_commits.include? submit_tag_hash then
              latest[:commit] = submit_tag_hash
              date = `git log -1 --format='%cI' '#{submit_tag_hash}'`.strip
              latest[:date] = Time.parse(date)
            end
          else
            # we don't have a submission tag, so we need to find the commit
            # that is the latest submission.
            @check_files.each do |file|
              date_commit = `git log -1 --format='%cI\n%H' '#{remote_ref}' -- '#{file}'`.strip
              date = date_commit.lines.first
              commit = date_commit.lines.last

              next if date.nil?
              date = Time.parse(date)
              next if commit.nil?

              # Do not count this submission, it it's part of the ignore commits
              next if @ignored_commits.include? commit

              if latest[:date].nil? then
                latest[:date] = date
                latest[:commit] = commit
              elsif date > latest[:date] then
                latest[:date] = date
                latest[:commit] = commit
              end
            end
          end
          submission[:commit] = latest[:commit]
          submission[:committed_at] = latest[:date]

          # Check for push events for timely submission
          # Students may push after the deadline and claim it was one time.
          if submission[:commit] && !@ignored_commits.include?(submission[:commit]) then
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
                    if submission[:commit] == commit then
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
                    if commit[:sha] == submission[:commit] then
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

          # If the user submitted, push a tag
          if @tag_submission and !submit_tag_hash and ( (@check_submit and submission[:submitted] and submission[:commit]) or (!@check_submit and !@check_files.empty?) ) then
            ref = submission[:commit]
            ref = remote_ref if ref.nil?
            if system('git', 'tag', submit_tag, ref) then
              system('git', 'push', remote, "#{submit_tag}:#{@tag_submission}")
            end
          end
        end

        # If we fetched, compress the repo
        if self.options[:fetch] then
          system('nice', 'git', 'gc', out: File::NULL, err: File::NULL)
        end
      end

      def slip_days(committed_at, pushed_at)
        if committed_at and !pushed_at then
          # For some reason GitHub did not have a push event. Fall back to commit date
          date = committed_at
        else
          date = pushed_at
        end

        days_late = 0
        if date then
          diff = date - @deadline
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
