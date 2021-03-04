require 'csv'

module TeachersPet
  module Actions
    class CollectSubmissions < Base

      def initialize(opts={})
        super(opts)

        @repository = self.options[:repository]
        @organization = self.options[:organization]

        self.init_client
        @students = self.read_students_file

        @report_filename = self.options[:report]
        @validate_teams = self.options[:team_validation]

        @submit_csv = self.options[:submit_csv]
        if @submit_csv then
          csv = CSV.read(@submit_csv)
          @submission_hashes = Hash.new
          csv.each do |row|
            @submission_hashes[row[0]] = row[1]
          end
        end

        @tag_submission = self.options[:push_submission_tag]

        @ignored_commits = self.options[:ignore_commits]
        @ignored_commits = Array.new if @ignored_commits.nil?
        @ignored_students = self.options[:ignore_students]
      end

      def collect_submissions
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
            if @ignore_students.include? student then
              $stderr.puts " skipping #{student}"
              next
            end
          end

          if @submission_hashes && !@submission_hashes.key?(student) then
            $stderr.puts " skipping #{student}"
            next
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

        puts "Colling submissions:"
        @submissions = Hash.new
        remotes.each do |remote|
          puts " -> #{remote}"

          submission = Hash.new
          @submissions[remote] = submission
          repo_name = "#{@organization}/#{remote}-#{@repository}"
          remote_ref = "#{remote}/master"
          submit_tag = "#{remote}/#{@tag_submission}"

          # Get the hash of the submission tag
          if @tag_submission then
            unless `git tag -l #{submit_tag}`.strip.empty? then
              submit_tag_hash = `git log -1 --format='%H' '#{submit_tag}' --`.strip
            end
          end

          # Fetch the latest changes
          if self.options[:fetch] then
            system('git', 'fetch', '--no-tags', '--prune', remote)
          end

          commits = Array.new
          commit_log = `git log --format='%cI, %H' '#{remote_ref}'`.strip
          commit_log.each_line do |line|
            values = line.split(', ')
            commits.push( {:hash => values[1].strip, :date => Time.parse(values[0].strip)} )
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
          elsif @submission_hashes && @submission_hashes.key?(remote)
            submit_hash = @submission_hashes[remote]
            found_hash = false
            commits.each do |commit|
              if commit[:hash] == submit_hash then
                found_hash = true
                latest[:date] = commit[:date]
                latest[:commit] = commit[:hash]
                break
              end
            end
            $stderr.puts "warning: unable to locate submission hash #{submit_hash} for #{remote}" unless found_hash
          else
            # we don't have a submission tag, so we need to find the commit
            # that is the latest submission.
            next if commits.first.nil?

            date = commits.first[:date]
            commit = commits.first[:hash]

            # Do not count this submission, it it's part of the ignore commits
            next if @ignored_commits.include? commit

            latest[:date] = date
            latest[:commit] = commit
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

                hashes = `git log --format='%H' #{before}..#{head} 2>&1`.strip
                if $?.success?
                  hashes.each_line do |commit|
                    commit = commit.strip
                    if submission[:commit] == commit then
                      found_commit_push = true;
                      break
                    end
                  end
                else
                  # looks like the student modified the history...
                  submission[:rewrite_history] = hashes

                  # let's try to find the commit in what GitHub gives us...
                  hashes = event[:payload][:commits]
                  hashes.each do |commit|
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

          # If the user submitted, push a tag
          if submission[:commit].nil? then
            $stderr.puts "  \\ warning: no submission, ignoring: #{remote}"
          elsif submit_tag_hash then
            $stderr.puts "  \\ warning: submission tag exists, ignoring: #{remote} (#{submit_tag_hash})"
          elsif @tag_submission and !submit_tag_hash and submission[:commit] then
            ref = submission[:commit]
            ref = remote_ref if ref.nil?
            puts "  \\ tagging submission #{remote} (#{ref})"
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

      def write_report
        CSV.open(@report_filename, "wb") do |csv|
          csv << ['remote', 'submitted', 'commit', 'committed_at', 'pushed_at', 'rewrite_history']
          @submissions.each do |remote, submission|
            date = submission[:committed_at]
            date = date.strftime('%F %T') if date
            push = submission[:pushed_at]
            push = push.strftime('%F %T') if push
            csv << [remote, submission[:submitted].to_s.upcase, submission[:commit], date, push, submission[:rewrite_history]]
          end
        end
      end

      def run
        self.collect_submissions
        self.write_report
      end
    end
  end
end
