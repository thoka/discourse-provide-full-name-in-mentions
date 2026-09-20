# frozen_string_literal: true

RSpec.describe ProblemCheck::MentionFullNamesNotCollected do
  before { enable_current_plugin }

  it "warns when the site never asks for a name" do
    SiteSetting.full_name_requirement = "hidden_at_signup"
    expect(described_class.new.call).to be_present
  end

  it "stays quiet when names are required" do
    SiteSetting.full_name_requirement = "required_at_signup"
    expect(described_class.new.call).to be_blank
  end

  it "stays quiet when names are optional" do
    SiteSetting.full_name_requirement = "optional_at_signup"
    expect(described_class.new.call).to be_blank
  end

  it "stays quiet when the plugin is disabled" do
    SiteSetting.full_name_requirement = "hidden_at_signup"
    SiteSetting.provide_full_name_in_mentions_enabled = false
    expect(described_class.new.call).to be_blank
  end
end
