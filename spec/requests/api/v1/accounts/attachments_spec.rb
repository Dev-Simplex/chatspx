require 'rails_helper'

RSpec.describe 'Attachments API team isolation', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account, team_message_isolation: true) }
  let(:team_a) { create(:team, account: account, allow_auto_assign: false) }
  let(:team_b) { create(:team, account: account, allow_auto_assign: false) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, team: team_a) }

  before { create(:inbox_member, user: agent, inbox: inbox) }

  def create_media(team)
    message = create(:message, account: account, inbox: inbox, conversation: conversation,
                               content: "https://exemplo.com/#{team.id}")
    message.update!(team_id: team.id)
    attachment = message.attachments.new(account_id: account.id, file_type: :image)
    attachment.file.attach(io: Rails.root.join('spec/assets/sample.png').open, filename: "#{team.id}.png", content_type: 'image/png')
    attachment.save!
    [message, attachment]
  end

  it 'filters gallery media and links and honors the inbox exemption' do
    own_message, own_attachment = create_media(team_a)
    other_message, other_attachment = create_media(team_b)
    headers = agent.create_new_auth_token

    get "/api/v1/accounts/#{account.id}/attachments", headers: headers
    expect(response.parsed_body['payload'].pluck('id')).to contain_exactly(own_attachment.id)

    get "/api/v1/accounts/#{account.id}/attachments/links", headers: headers
    expect(response.parsed_body['payload'].pluck('id')).to contain_exactly(own_message.id)

    create(:inbox_isolation_exemption, inbox: inbox, user: agent, isolation_type: 'team_message')
    Rails.cache.clear

    get "/api/v1/accounts/#{account.id}/attachments", headers: headers
    expect(response.parsed_body['payload'].pluck('id')).to contain_exactly(own_attachment.id, other_attachment.id)

    get "/api/v1/accounts/#{account.id}/attachments/links", headers: headers
    expect(response.parsed_body['payload'].pluck('id')).to contain_exactly(own_message.id, other_message.id)
  end
end
