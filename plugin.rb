# frozen_string_literal: true

# name: discourse-provide-full-name-in-mentions
# about: Adds a data-full-name attribute to @mentions in cooked posts
# version: 0.3.0
# authors: Thomas Kalka
# url: https://github.com/thoka/discourse-provide-full-name-in-mentions

enabled_site_setting :provide_full_name_in_mentions_enabled

module ::DiscourseProvideFullNameInMentions
  PLUGIN_NAME = "discourse-provide-full-name-in-mentions"
end

require_relative "lib/discourse_provide_full_name_in_mentions/engine"

after_initialize do
  register_problem_check ProblemCheck::MentionFullNamesNotCollected

  reloadable_patch do
    ::PrettyText.singleton_class.prepend(
      ::DiscourseProvideFullNameInMentions::PrettyTextExtension,
    )
    ::Jobs::ChangeDisplayName.prepend(
      ::DiscourseProvideFullNameInMentions::ChangeDisplayNameExtension,
    )
  end
end
