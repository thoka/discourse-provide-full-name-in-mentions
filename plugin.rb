# frozen_string_literal: true

# name: discourse-provide-full-name-in-mentions
# about: Provides full name in mentions
# version: 0.1
# authors: Thomas Kalka 
# url: https://github.com/thoka/discourse-provide-full-name-in-mentions

require_dependency 'pretty_text'

module ::PrettyText 
    private

    def self.add_mentions(doc, user_id: nil)
      elements = doc.css("span.mention")
      names = elements.map { |element| element.text[1..-1] }
  
      mentions = lookup_mentions(names, user_id: user_id)
  
      elements.each do |element|
        name = element.text[1..-1]
        name.downcase!
  
        if mention = mentions[name]
          element.name = "a"
  
          element.children = PrettyText::Helpers.format_username(element.children.text)
          element["data-full-name"] = mention.full_name
          case mention.type
          when USER_TYPE
            element["href"] = "#{Discourse.base_path}/u/#{UrlHelper.encode_component(name)}"
          when GROUP_MENTIONABLE_TYPE
            element["class"] = "mention-group notify"
            element["href"] = "#{Discourse.base_path}/groups/#{UrlHelper.encode_component(name)}"
          when GROUP_TYPE
            element["class"] = "mention-group"
            element["href"] = "#{Discourse.base_path}/groups/#{UrlHelper.encode_component(name)}"
          end
        end
      end
    end
  
    def self.lookup_mentions(names, user_id: nil)
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
          user_type: USER_TYPE,
          group_type: GROUP_TYPE,
          group_mentionable_type: GROUP_MENTIONABLE_TYPE,
          levels: Group.alias_levels(user),
          user_id: user_id,
        )
  
      mentions = {}
      results.each { |result| mentions[result.handle] = result }
      mentions
    end
end
