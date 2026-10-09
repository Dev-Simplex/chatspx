# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InternalChannels::SharedMediaService do
  let(:account) { create(:account) }
  let(:alice) { create(:user, account: account, role: :agent) }
  let(:channel) { create(:internal_channel, :with_two_members, account: account, user_a: alice) }

  def message_with(filename, content_type, content: '')
    message = channel.messages.new(user: alice, content: content)
    message.attachments.attach(io: StringIO.new('x'), filename: filename, content_type: content_type)
    message.save!
    message
  end

  it 'splits images/videos (media) from the other files (docs)' do
    photo = message_with('foto.png', 'image/png')
    message_with('video.mp4', 'video/mp4')
    message_with('proposta.pdf', 'application/pdf')

    result = described_class.new(channel: channel).perform

    expect(result[:media].pluck(:filename)).to contain_exactly('foto.png', 'video.mp4')
    expect(result[:docs].pluck(:filename)).to eq(['proposta.pdf'])
    expect(result[:media].find { |f| f[:filename] == 'foto.png' }[:message_id]).to eq(photo.id)
  end

  it 'extracts links from the text, without trailing punctuation, with the domain' do
    message = create(:internal_message, internal_channel: channel, user: alice,
                                        content: 'veja https://www.exemplo.com.br/a?b=1. e http://x.io')

    links = described_class.new(channel: channel).perform[:links]

    expect(links.pluck(:url)).to eq(['https://www.exemplo.com.br/a?b=1', 'http://x.io'])
    expect(links.first[:domain]).to eq('exemplo.com.br')
    expect(links.first[:message_id]).to eq(message.id)
  end

  it 'ignores deleted messages' do
    message_with('foto.png', 'image/png').soft_delete!
    create(:internal_message, internal_channel: channel, user: alice, content: 'https://a.com').soft_delete!

    result = described_class.new(channel: channel).perform

    expect(result.values).to all(be_empty)
  end
end
