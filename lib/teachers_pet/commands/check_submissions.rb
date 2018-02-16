module TeachersPet
  class Cli
    option :organization, required: true
    option :repository, required: true

    option :deadline, required: true, banner: 'DATE', desc: "Deadline for the submission: MM/DD/YYYY HH:MM"
    option :report, required: true, banner: 'FILE', desc: "CSV file to write the submission deadlines to."
    option :file_exists, banner: 'FILE', desc: "If file exists, then the assignment was submitted."
    option :fetch, desc: "Fetch the latest from each student's repository."

    students_option
    common_options

    desc 'check_submissions', "Check the student repositories for timely submission."
    def check_submissions(*check_files)
      TeachersPet::Actions::CheckSubmissions.new(check_files, options).run
    end
  end
end
