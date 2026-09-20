# frozen_string_literal: true

module DiscourseProvideFullNameInMentions
  # Brings data-full-name on already-cooked content in line with the database,
  # without rebaking.
  #
  # Rebaking re-runs the whole pipeline -- oneboxes, the post analyzer, image
  # processing -- to change a single attribute. Core declines to do that for the
  # equivalent username and display-name updates and patches the cooked HTML
  # with Nokogiri instead; see the comment above
  # Jobs::UpdateUsername#update_cooked. This takes the same approach, and like
  # both core jobs it covers post revisions as well as posts.
  #
  # It syncs toward whatever a rebake would produce right now: enabled, every
  # resolvable mention gets a current data-full-name; disabled, the attribute is
  # removed. Records needing no change are never written.
  module CookedSync
    BATCH_SIZE = 500

    Result = Struct.new(:posts_scanned, :posts_changed, :revisions_scanned, :revisions_changed) do
      def to_s
        "posts #{posts_changed}/#{posts_scanned}, revisions #{revisions_changed}/#{revisions_scanned}"
      end
    end

    # Yields the Result after each batch when a block is given, for progress
    # reporting. Returns the final Result.
    def self.call(
      enabled: SiteSetting.provide_full_name_in_mentions_enabled,
      dry_run: false,
      delay: 0,
      &progress
    )
      result = Result.new(0, 0, 0, 0)
      base = Discourse.base_path.presence

      sync_posts(result, base, enabled, dry_run, delay, &progress)
      sync_revisions(result, base, enabled, dry_run, delay, &progress)

      result
    end

    # Only posts whose cooked already contains a linked mention can need work.
    def self.sync_posts(result, base, enabled, dry_run, delay)
      Post
        .where("cooked LIKE ?", "%class=\"mention%")
        .find_in_batches(batch_size: BATCH_SIZE) do |posts|
          docs = posts.filter_map do |post|
            doc = Nokogiri::HTML5.fragment(post.cooked)
            anchors = doc.css("a.mention, a.mention-group")
            anchors.empty? ? nil : [post, [[doc, anchors]]]
          end

          apply_to_batch(docs, base, enabled) do |post, pairs, touched|
            result.posts_scanned += 1
            next unless touched

            result.posts_changed += 1
            next if dry_run

            begin
              post.update_columns(cooked: pairs.first[0].to_html)
            rescue => e
              Discourse.warn_exception(e, message: "Failed to update post with id #{post.id}")
            end
          end

          yield result if block_given?
          sleep delay if delay > 0
        end
    end

    # modifications is a YAML-serialised text column, so matching the full
    # `class="mention` needs to know how YAML quoted the HTML. Matching the bare
    # word is quoting-agnostic and gives a superset, which the Nokogiri pass
    # below narrows down for real.
    def self.sync_revisions(result, base, enabled, dry_run, delay)
      PostRevision
        .where("modifications LIKE ?", "%mention%")
        .find_in_batches(batch_size: BATCH_SIZE) do |revisions|
          docs =
            revisions.filter_map do |revision|
              versions = revision.modifications["cooked"]
              next if versions.blank?

              pairs =
                versions.map do |cooked|
                  next if cooked.blank?
                  doc = Nokogiri::HTML5.fragment(cooked)
                  anchors = doc.css("a.mention, a.mention-group")
                  anchors.empty? ? nil : [doc, anchors]
                end

              pairs.any? ? [revision, pairs] : nil
            end

          apply_to_batch(docs, base, enabled) do |revision, pairs, touched|
            result.revisions_scanned += 1
            next unless touched

            result.revisions_changed += 1
            next if dry_run

            begin
              versions = revision.modifications["cooked"]
              pairs.each_with_index { |pair, i| versions[i] = pair[0].to_html if pair }
              revision.modifications["cooked"] = versions
              revision.save!
            rescue => e
              Discourse.warn_exception(
                e,
                message: "Failed to update post revision with id #{revision.id}",
              )
            end
          end

          yield result if block_given?
          sleep delay if delay > 0
        end
    end

    # docs is [[record, [[doc, anchors], ...]], ...]. Looks every handle in the
    # batch up at once, then yields each record with whether anything changed.
    def self.apply_to_batch(docs, base, enabled)
      return if docs.empty?

      handles = { user: Set.new, group: Set.new }
      docs.each do |_record, pairs|
        pairs.each do |pair|
          next if pair.nil?
          pair[1].each do |a|
            kind, handle = mention_target(a["href"], base)
            handles[kind] << handle if kind
          end
        end
      end

      names = lookup_full_names(handles)

      docs.each do |record, pairs|
        touched =
          pairs.count { |pair| pair && apply!(pair[1], names, base, enabled) }.positive?
        yield record, pairs, touched
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
