# frozen_string_literal: true

RSpec.describe Jobs::ChangeDisplayName do
  before do
    enable_current_plugin
    # Mentions by other people are found through user_actions, which specs
    # disable by default for speed. Core's update_username_spec does the same.
    UserActionManager.enable
    Jobs.run_immediately!
  end

  fab!(:author) { Fabricate(:user) }
  fab!(:ada) { Fabricate(:user, username: "ada", name: "Ada Lovelace") }
  fab!(:topic) { Fabricate(:topic, user: author) }

  # Renaming through the model fires core's after_update, which enqueues this
  # job -- the path a real rename takes.
  def rename!(user, name)
    user.update!(name: name)
  end

  it "refreshes mentions by other people" do
    post = create_post(user: author, topic: topic, raw: "hi @ada")
    expect(post.cooked).to include('data-full-name="Ada Lovelace"')

    rename!(ada, "Ada King")

    expect(post.reload.cooked).to include('data-full-name="Ada King"')
  end

  it "refreshes self-mentions, which are not recorded in user_actions" do
    post = create_post(user: ada, topic: topic, raw: "hi @ada, that's me")
    expect(post.cooked).to include('data-full-name="Ada Lovelace"')

    rename!(ada, "Ada King")

    expect(post.reload.cooked).to include('data-full-name="Ada King"')
  end

  it "refreshes revision history" do
    post = create_post(user: author, topic: topic, raw: "first, hi @ada")
    PostRevisor.new(post).revise!(
      author,
      { raw: "second, hi @ada again" },
      revised_at: post.updated_at + SiteSetting.editing_grace_period + 1.second,
    )

    rename!(ada, "Ada King")

    cooked = PostRevision.find_by(post_id: post.id).reload.modifications["cooked"].join
    expect(cooked).to include("Ada King")
    expect(cooked).not_to include("Ada Lovelace")
  end

  it "leaves mentions alone when the plugin is disabled" do
    post = create_post(user: author, topic: topic, raw: "hi @ada")
    SiteSetting.provide_full_name_in_mentions_enabled = false

    rename!(ada, "Ada King")

    expect(post.reload.cooked).to include('data-full-name="Ada Lovelace"')
  end
end
