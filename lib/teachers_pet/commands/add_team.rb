module TeachersPet
  class Cli
    option :organization, required: true
    option :repository, required: true, banner: 'OWNER/REPO'
    option :team, required: true, banner: 'TEAM', desc: "The team to add to the repository."
    option :permission, required: true, banner: 'pull/push/admin', desc: "The permission to grant the team in the repository."

    students_option
    common_options

    desc "add_team", "Add a team to a repository."
    def add_team
      TeachersPet::Actions::AddTeam.new(options).run
    end
  end
end
