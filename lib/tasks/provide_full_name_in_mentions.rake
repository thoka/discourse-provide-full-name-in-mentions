# frozen_string_literal: true

# Patch data-full-name into already-cooked posts without rebaking.
#
#   bin/rake provide_full_name_in_mentions:sync
#   bin/rake provide_full_name_in_mentions:sync[2]   # sleep 2s between batches
#   DRY_RUN=1 bin/rake provide_full_name_in_mentions:sync
#
# See DiscourseProvideFullNameInMentions::CookedSync for what "sync" means.

desc "Sync data-full-name in cooked posts without rebaking"
task "provide_full_name_in_mentions:sync", [:delay] => :environment do |_, args|
  dry_run = ENV["DRY_RUN"].present?
  enabled = SiteSetting.provide_full_name_in_mentions_enabled
  verb = dry_run ? "would change" : "changed"

  puts "Plugin is #{enabled ? "enabled" : "disabled"}: #{enabled ? "adding/updating" : "removing"} data-full-name"
  puts "DRY RUN, nothing will be written" if dry_run

  result =
    DiscourseProvideFullNameInMentions::CookedSync.call(
      enabled: enabled,
      dry_run: dry_run,
      delay: args[:delay].to_i,
    ) { |r| print "\rscanned #{r.scanned}, #{verb} #{r.changed}"; $stdout.flush }

  puts "\nDone. Scanned #{result.scanned} posts, #{verb} #{result.changed}."
end
