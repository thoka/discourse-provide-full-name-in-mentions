# frozen_string_literal: true

RSpec.describe PrettyText do
  before { enable_current_plugin }

  fab!(:user) { Fabricate(:user, username: "ada", name: "Ada Lovelace") }

  fab!(:mentionable_group) do
    Fabricate(
      :group,
      name: "engineers",
      full_name: "The Engineers",
      mentionable_level: Group::ALIAS_LEVELS[:everyone],
    )
  end

  fab!(:plain_group) do
    Fabricate(
      :group,
      name: "lurkers",
      full_name: "The Lurkers",
      mentionable_level: Group::ALIAS_LEVELS[:nobody],
    )
  end

  it "adds the user's name to user mentions" do
    expect(PrettyText.cook("hi @ada")).to eq(
      '<p>hi <a class="mention" data-full-name="Ada Lovelace" href="/u/ada">@ada</a></p>',
    )
  end

  it "adds the group's full name to mentionable group mentions" do
    expect(PrettyText.cook("hi @engineers")).to eq(
      '<p>hi <a class="mention-group notify" data-full-name="The Engineers" href="/groups/engineers">@engineers</a></p>',
    )
  end

  it "adds the group's full name to groups that cannot be mentioned" do
    expect(PrettyText.cook("hi @lurkers")).to eq(
      '<p>hi <a class="mention-group" data-full-name="The Lurkers" href="/groups/lurkers">@lurkers</a></p>',
    )
  end

  it "leaves unknown mentions untouched" do
    expect(PrettyText.cook("hi @nobody_here")).to eq(
      '<p>hi <span class="mention">@nobody_here</span></p>',
    )
  end

  it "emits an empty attribute when no name is set" do
    Fabricate(:user, username: "anon", name: nil)

    expect(PrettyText.cook("hi @anon")).to eq(
      '<p>hi <a class="mention" data-full-name="" href="/u/anon">@anon</a></p>',
    )
  end

  context "when the plugin is disabled" do
    before { SiteSetting.provide_full_name_in_mentions_enabled = false }

    # Both add_mentions and lookup_mentions must fall back to core together.
    # This override's lookup_mentions returns the whole result row where core
    # returns a type string, so if only one of them falls back, core's
    # `case type` matches no branch. Core sets `element.name = "a"` before that
    # case, so the mention renders as <a class="mention">@name</a> with no href
    # at all -- a dead link. Asserting the full anchor catches that, where
    # checking only for the absence of data-full-name would not.
    it "falls back to core output for users" do
      expect(PrettyText.cook("hi @ada")).to eq('<p>hi <a class="mention" href="/u/ada">@ada</a></p>')
    end

    it "falls back to core output for groups" do
      expect(PrettyText.cook("hi @engineers")).to eq(
        '<p>hi <a class="mention-group notify" href="/groups/engineers">@engineers</a></p>',
      )
    end
  end
end
