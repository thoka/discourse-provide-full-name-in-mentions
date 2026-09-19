# frozen_string_literal: true

module DiscourseProvideFullNameInMentions
  # Overrides the two private `PrettyText` singleton methods that build mention
  # links, so that each `<a class="mention">` also carries the user's or group's
  # full name in a `data-full-name` attribute.
  #
  # Both methods fall back to `super` when the plugin is disabled. They have to
  # be gated together: this `lookup_mentions` returns the whole result row where
  # core returns just the type string, so core's `add_mentions` cannot consume
  # this `lookup_mentions` and vice versa.
  module PrettyTextExtension
    def add_mentions(doc, user_id: nil)
      return super unless SiteSetting.provide_full_name_in_mentions_enabled

      elements = doc.css("span.mention")
      names = elements.map { |element| element.text[1..-1] }

      mentions = lookup_mentions(names, user_id: user_id)

      elements.each do |element|
        name = element.text[1..-1]
        name.downcase!

        next unless (mention = mentions[name])

        element.name = "a"
        element.children = ::PrettyText::Helpers.format_username(element.children.text)
        element["data-full-name"] = mention.full_name

        case mention.type
        when ::PrettyText::USER_TYPE
          element["href"] = "#{Discourse.base_path}/u/#{UrlHelper.encode_component(name)}"
        when ::PrettyText::GROUP_MENTIONABLE_TYPE
          element["class"] = "mention-group notify"
          element["href"] = "#{Discourse.base_path}/groups/#{UrlHelper.encode_component(name)}"
        when ::PrettyText::GROUP_TYPE
          element["class"] = "mention-group"
          element["href"] = "#{Discourse.base_path}/groups/#{UrlHelper.encode_component(name)}"
        end
      end
    end

    def lookup_mentions(names, user_id: nil)
      return super unless SiteSetting.provide_full_name_in_mentions_enabled
      return {} if names.blank?

      sql = <<~SQL
        (
          SELECT
            :user_type AS type,
            username_lower AS handle,
            name AS full_name
          FROM users
          WHERE username_lower IN (:names) AND staged = false
        )
        UNION
        (
          SELECT
            :group_type AS type,
            lower(name) AS handle,
            full_name
          FROM groups
        )
        UNION
        (
          SELECT
            :group_mentionable_type AS type,
            lower(name) AS handle,
            full_name
          FROM groups
          WHERE lower(name) IN (:names) AND (#{Group.mentionable_sql_clause(include_public: false)})
        )
        ORDER BY type
      SQL

      user = User.find_by(id: user_id)
      names.each(&:downcase!)

      results =
        DB.query(
          sql,
          names: names,
          user_type: ::PrettyText::USER_TYPE,
          group_type: ::PrettyText::GROUP_TYPE,
          group_mentionable_type: ::PrettyText::GROUP_MENTIONABLE_TYPE,
          levels: Group.alias_levels(user),
          user_id: user_id,
        )

      mentions = {}
      results.each { |result| mentions[result.handle] = result }
      mentions
    end
  end
end
