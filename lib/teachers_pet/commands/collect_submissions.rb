module TeachersPet
  class Cli
    option :organization, required: true
    option :repository, required: true

    option :report, required: true, banner: 'FILE', desc: "CSV file to write the submission deadlines to."
    option :submit_csv, banner: 'FILE', desc: "CSV file with team name (first column) and commit hash (second column)."
    option :ignore_commits, type: :array, banner: 'COMMITs', desc: "Ignored COMMITs."
    option :fetch, desc: "Fetch the latest from each student's repository."
    option :push_submission_tag, banner: 'TAG', desc: "For each repository, create a tag and push it to the student's repository."
    option :ignore_students, type: :array, banner: 'STUDENTs', desc: "Ignore these students"
    option :team_validation, type: :boolean, default: true, desc: 'Do not check if student teams are valid.'

    students_option
    common_options

    desc 'collect_submissions', "Check the student repositories for timely submission."
    def collect_submissions
      TeachersPet::Actions::CollectSubmissions.new(options).run
    end
  end
end
