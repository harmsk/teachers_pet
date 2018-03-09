module TeachersPet
  class Cli
    option :organization, required: true
    option :repository, required: true

    option :deadline, required: true, banner: 'DATE', desc: "Deadline for the submission: MM/DD/YYYY HH:MM"
    option :report, required: true, banner: 'FILE', desc: "CSV file to write the submission deadlines to."
    option :submit_file, banner: 'FILE', desc: "If file exists, then the assignment was submitted."
    option :ignore_commit, banner: 'COMMIT', desc: "Ignore COMMIT and do not count as a submission."
    option :fetch, desc: "Fetch the latest from each student's repository."
    option :team_validation, type: :boolean, default: true, desc: 'Do not check if student teams are valid.'

    students_option
    common_options

    desc 'check_submissions', "Check the student repositories for timely submission."
    def check_submissions(*check_files)
      TeachersPet::Actions::CheckSubmissions.new(check_files, options).run
    end
  end
end
