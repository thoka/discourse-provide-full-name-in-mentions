# frozen_string_literal: true

module DiscourseProvideFullNameInMentions
  # Core enqueues Jobs::ChangeDisplayName from an after_update on the User model
  # (app/models/user.rb), so it runs for every name change regardless of which
  # code path made it. The job rewrites the name in quotes only -- it selects
  # posts via a quoted_posts join -- because before this plugin no baked mention
  # contained a name.
  #
  # Extending it rather than adding a second callback reuses that enqueue and
  # its `cluster_concurrency 1`, which already serialises rapid successive
  # renames of the same user.
  module ChangeDisplayNameExtension
    def execute(args)
      super

      return unless SiteSetting.provide_full_name_in_mentions_enabled

      CookedSync.for_user(args[:user_id])
    rescue => e
      # Never let the mention pass take down core's quote rewriting, which has
      # already run by this point.
      Discourse.warn_exception(
        e,
        message: "Failed to sync mention full names for user #{args[:user_id]}",
      )
    end
  end
end
