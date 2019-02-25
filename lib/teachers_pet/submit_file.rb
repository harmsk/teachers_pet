module TeachersPet
  class SubmitFile

    def self.inherited(subclass)
      @descendants ||= []
      @descendants << subclass
    end

    def self.descendants
      @descendants
    end

    def verify(contents)
      return true
    end
  end
end
