# frozen_string_literal: true

module DiscourseProvideFullNameInMentions
  # Brings data-full-name on already-cooked posts in line with the database,
  # without rebaking.
  #
  # Rebaking re-runs the whole pipeline -- oneboxes, the post analyzer, image
  # processing -- to change a single attribute. Core declines to do that for the
  # equivalent username and display-name updates and patches the cooked HTML
  # with Nokogiri instead; see the comment above
  # Jobs::UpdateUsername#update_cooked. This takes the same approach.
  #
  # It syncs toward whatever a rebake would produce right now: enabled, every
  # resolvable mention gets a current data-full-name; disabled, the attribute is
  # removed. Posts needing no change are never written.
  module CookedSync
    BATCH_SIZE = 500

    Result = Struct.new(:scanned, :changed)

    # Yields a Result after each batch when a block is given, for progress
    # reporting. Returns the final Result.
    def self.call(enabled: SiteSetting.provide_full_name_in_mentions_enabled, dry_run: false, delay: 0)
      result = Result.new(0, 0)
      base = Discourse.base_path.presence

      # Only posts already containing a linked mention can need anything.
      Post
        .where("cooked LIKE ?", "%class=\"mention%")
        .find_in_batches(batch_size: BATCH_SIZE) do |posts|
          process_batch(posts, result, base, enabled, dry_run)
          yield result if block_given?
          sleep delay if delay > 0
        end

      result
    end

    def self.process_batch(posts, result, base, enabled, dry_run)
      parsed = []
      handles = { user: Set.new, group: Set.new }

      posts.each do |post|
        doc = Nokogiri::HTML5.fragment(post.cooked)
        anchors = doc.css("a.mention, a.mention-group")
        next if anchors.empty?

        parsed << [post, doc, anchors]
        anchors.each do |a|
          kind, handle = mention_target(a["href"], base)
          handles[kind] << handle if kind
        end
      end

      return if parsed.empty?

      names = lookup_full_names(handles)

      parsed.each do |post, doc, anchors|
        result.scanned += 1
        next unless apply!(anchors, names, base, enabled)

        result.changed += 1
        post.update_columns(cooked: doc.to_html) unless dry_run
      end
    end

    # Returns true when any attribute actually changed.
    def self.apply!(anchors, names, base, enabled)
      touched = false

      anchors.each do |a|
        kind, handle = mention_target(a["href"], base)
        next if kind.nil?

        if enabled
          # A handle absent from the lookup is a user or group that has since
          # been renamed or removed. Leave it alone rather than blanking it.
          next unless names[kind].key?(handle)

          desired = names[kind][handle].to_s
          next if a["data-full-name"] == desired

          a["data-full-name"] = desired
          touched = true
        elsif a.key?("data-full-name")
          a.delete("data-full-name")
          touched = true
        end
      end

      touched
    end

    # "/u/ada" => [:user, "ada"], "/groups/engineers" => [:group, "engineers"]
    # nil for anything else, including offsite hrefs and unlinked mentions.
    def self.mention_target(href, base_path)
      return nil if href.blank?

      path = href.dup
      path = path.delete_prefix(base_path) if base_path && path.start_with?(base_path)

      if (handle = path[%r{\A/u/([^/?#]+)\z}, 1])
        [:user, CGI.unescape(handle).downcase]
      elsif (handle = path[%r{\A/groups/([^/?#]+)\z}, 1])
        [:group, CGI.unescape(handle).downcase]
      end
    end

    def self.lookup_full_names(handles)
      users = {}
      groups = {}

      if handles[:user].any?
        User
          .where(username_lower: handles[:user].to_a)
          .pluck(:username_lower, :name)
          .each { |handle, name| users[handle] = name }
      end

      if handles[:group].any?
        Group
          .where("lower(name) IN (?)", handles[:group].to_a)
          .pluck(Arel.sql("lower(name)"), :full_name)
          .each { |handle, full_name| groups[handle] = full_name }
      end

      { user: users, group: groups }
    end
  end
end
