# frozen_string_literal: true

RSpec.describe "provide_full_name_in_mentions:sync" do
  before do
    enable_current_plugin
    STDOUT.stubs(:write)
  end

  fab!(:author) { Fabricate(:user) }
  fab!(:ada) { Fabricate(:user, username: "ada", name: "Ada Lovelace") }
  fab!(:engineers) do
    Fabricate(
      :group,
      name: "engineers",
      full_name: "The Engineers",
      mentionable_level: Group::ALIAS_LEVELS[:everyone],
    )
  end

  def sync = invoke_rake_task("provide_full_name_in_mentions:sync")

  def post_mentioning(raw)
    Fabricate(:post, user: author, raw: raw)
  end

  # Cooks a post as it would have been before the plugin was installed.
  def legacy_post(raw)
    SiteSetting.provide_full_name_in_mentions_enabled = false
    post = post_mentioning(raw)
    SiteSetting.provide_full_name_in_mentions_enabled = true
    post
  end

  it "backfills posts cooked before the plugin was installed" do
    post = legacy_post("hi @ada")
    expect(post.cooked).not_to include("data-full-name")

    sync

    expect(post.reload.cooked).to include('data-full-name="Ada Lovelace"')
  end

  it "backfills group mentions" do
    post = legacy_post("hi @engineers")

    sync

    expect(post.reload.cooked).to include('data-full-name="The Engineers"')
  end

  it "refreshes a name that changed after baking" do
    post = post_mentioning("hi @ada")
    expect(post.cooked).to include('data-full-name="Ada Lovelace"')

    # update_columns so the core ChangeDisplayName job does not run; we are
    # testing that this task alone brings the cooked HTML back in line.
    ada.update_columns(name: "Ada King")

    sync

    expect(post.reload.cooked).to include('data-full-name="Ada King"')
  end

  it "removes the attribute when the plugin is disabled" do
    post = post_mentioning("hi @ada")
    expect(post.cooked).to include("data-full-name")

    SiteSetting.provide_full_name_in_mentions_enabled = false
    sync

    expect(post.reload.cooked).not_to include("data-full-name")
    expect(post.reload.cooked).to include('href="/u/ada"')
  end

  it "leaves mentions alone when the target no longer resolves" do
    post = post_mentioning("hi @ada")
    ada.update_columns(username: "renamed", username_lower: "renamed")

    sync

    # Still the old value rather than blanked: we cannot know the new name from
    # an href that no longer resolves, and an empty attribute would be worse.
    expect(post.reload.cooked).to include('data-full-name="Ada Lovelace"')
  end

  it "does not touch unlinked mentions" do
    post = legacy_post("hi @nobody_here")
    expect(post.cooked).to include('<span class="mention">@nobody_here</span>')

    expect { sync }.not_to raise_error
    expect(post.reload.cooked).to include('<span class="mention">@nobody_here</span>')
  end

  it "is idempotent" do
    post = legacy_post("hi @ada")
    sync
    after_first = post.reload.cooked

    sync

    expect(post.reload.cooked).to eq(after_first)
  end

  describe "post revisions" do
    # An edit inside the grace period rewrites in place; pushing revised_at past
    # it is what actually produces a PostRevision.
    def revise!(post, raw)
      PostRevisor.new(post).revise!(
        post.user,
        { raw: raw },
        revised_at: post.updated_at + SiteSetting.editing_grace_period + 1.second,
      )
      post.reload
    end

    it "refreshes names in revision history" do
      post = post_mentioning("first, hi @ada")
      revise!(post, "second, hi @ada again")

      revision = PostRevision.find_by(post_id: post.id)
      expect(revision.modifications["cooked"].join).to include("Ada Lovelace")

      ada.update_columns(name: "Ada King")
      sync

      cooked = revision.reload.modifications["cooked"].join
      expect(cooked).to include("Ada King")
      expect(cooked).not_to include("Ada Lovelace")
    end

    it "backfills revisions cooked before the plugin was installed" do
      post = legacy_post("first, hi @ada")
      SiteSetting.provide_full_name_in_mentions_enabled = false
      revise!(post, "second, hi @ada again")
      SiteSetting.provide_full_name_in_mentions_enabled = true

      revision = PostRevision.find_by(post_id: post.id)
      expect(revision.modifications["cooked"].join).not_to include("data-full-name")

      sync

      expect(revision.reload.modifications["cooked"].join).to include('data-full-name="Ada Lovelace"')
    end

    it "removes the attribute from revisions when disabled" do
      post = post_mentioning("first, hi @ada")
      revise!(post, "second, hi @ada again")

      SiteSetting.provide_full_name_in_mentions_enabled = false
      sync

      expect(PostRevision.find_by(post_id: post.id).modifications["cooked"].join).not_to include(
        "data-full-name",
      )
    end
  end

  it "writes nothing on a dry run" do
    post = legacy_post("hi @ada")
    before = post.cooked

    ENV["DRY_RUN"] = "1"
    begin
      sync
    ensure
      ENV.delete("DRY_RUN")
    end

    expect(post.reload.cooked).to eq(before)
  end
end
