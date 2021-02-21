module TeachersPet
  class Cli
    option :organization, required: true
    option :repository, required: true

    option :deadline, required: true, banner: 'DATE', desc: "Deadline for the submission: MM/DD/YYYY HH:MM"
    option :report, required: true, banner: 'FILE', desc: "CSV file to write the submission deadlines to."
    option :submit_file, banner: 'FILE', desc: "If file exists, then the assignment was submitted."
    option :submit_file_plugin, banner: 'FILE', desc: "Load SubmitFile plugin to verify submit file."
    # TODO: submit-tag support
    # option :submit_tag, banner: 'TAG', desc: "If tag exists, then the assignment was submitted."
    option :ignore_commits, type: :array, banner: 'COMMITs', desc: "Ignored COMMITs."
    option :fetch, desc: "Fetch the latest from each student's repository."
    option :push_submission_tag, banner: 'TAG', desc: "For each repository, create a tag and push it to the student's repository."
    option :ignore_students, type: :array, banner: 'STUDENTs', desc: "Ignore these students"
    option :team_validation, type: :boolean, default: true, desc: 'Do not check if student teams are valid.'

    students_option
    common_options

    desc 'collect_submissions', "Check the student repositories for timely submission."
    def collect_submissions(*check_files)
      TeachersPet::Actions::CollectSubmissions.new(check_files, options).run
    end
  end
end
