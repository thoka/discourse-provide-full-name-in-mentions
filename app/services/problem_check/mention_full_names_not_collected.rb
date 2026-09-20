# frozen_string_literal: true

# Core defaults full_name_requirement to hidden_at_signup, so a stock site never
# asks for a name. With this plugin installed and nothing collecting names,
# every user mention gets data-full-name="" and the plugin looks broken when it
# is in fact working with nothing.
class ProblemCheck::MentionFullNamesNotCollected < ProblemCheck
  self.priority = "low"

  def call
    return no_problem if !SiteSetting.provide_full_name_in_mentions_enabled
    return no_problem if SiteSetting.full_name_requirement != "hidden_at_signup"

    problem
  end
end
