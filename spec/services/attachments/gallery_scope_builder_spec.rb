require 'rails_helper'

RSpec.describe Attachments::GalleryScopeBuilder, type: :service do
  subject(:builder) { described_class.new(user: agent, account: account, filters: { type: 'image' }) }

  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:foreign_inbox) { create(:inbox, account: account) }

  before { create(:inbox_member, user: agent, inbox: inbox) }

  def create_attachment(target_inbox, file_type: :image, asset: 'sample.png', content_type: 'image/png')
    conversation = create(:conversation, account: account, inbox: target_inbox)
    message = create(:message, account: account, conversation: conversation, inbox: target_inbox)
    attachment = message.attachments.new(account_id: account.id, file_type: file_type)
    attachment.file.attach(io: Rails.root.join("spec/assets/#{asset}").open, filename: asset, content_type: content_type)
    attachment.save!
    attachment
  end

  it 'includes attachments from inboxes the agent is assigned to' do
    visible = create_attachment(inbox)
    expect(builder.deduped_scope.pluck(:id)).to include(visible.id)
  end

  it 'excludes attachments from inboxes the agent is not assigned to' do
    foreign = create_attachment(foreign_inbox)
    expect(builder.deduped_scope.pluck(:id)).not_to include(foreign.id)
  end

  it 'does not depend on Current (usable inside a job)' do
    create_attachment(inbox)
    Current.reset
    expect { builder.deduped_scope.to_a }.not_to raise_error
  end

  it 'returns an empty scope when the requester user is nil (deprovisioned)' do
    create_attachment(inbox)
    nil_user_builder = described_class.new(user: nil, account: account, filters: { type: 'image' })
    expect(nil_user_builder.deduped_scope.to_a).to be_empty
  end

  # §T5: uma data malformada não pode zerar a galeria silenciosamente.
  it 'ignores a malformed date filter instead of emptying the scope' do
    visible = create_attachment(inbox)
    garbage_builder = described_class.new(
      user: agent, account: account, filters: { type: 'image', after: 'lixo', before: 'também-lixo' }
    )
    expect(garbage_builder.deduped_scope.pluck(:id)).to include(visible.id)
  end

  it 'still applies a valid date filter' do
    old = travel_to(10.days.ago) { create_attachment(inbox) }
    recent = create_attachment(inbox)
    builder_with_date = described_class.new(
      user: agent, account: account, filters: { type: 'image', after: 2.days.ago.iso8601 }
    )
    ids = builder_with_date.deduped_scope.pluck(:id)
    expect(ids).to include(recent.id)
    expect(ids).not_to include(old.id)
  end

  # Isolamento por agente: num inbox isolado a galeria não pode vazar a mídia/link
  # da conversa de OUTRO agente (a superfície de conta não passa pelo guard).
  describe 'agent conversation isolation' do
    let(:owner) { create(:user, account: account, role: :agent) }
    # COM time: o isolamento e escopado pelo time da conversa
    # (Inbox#isolation_applies_to_team?). `allow_auto_assign: false` para o
    # AssignmentHandler nao inventar dono no caso "sem dono".
    let(:iso_team) { create(:team, account: account, allow_auto_assign: false) }

    def create_owned_attachment(assignee:, content: 'veja https://exemplo.com/x', team: iso_team)
      create(:team_member, team: team, user: assignee) if assignee && team && team.members.exclude?(assignee)
      conversation = create(:conversation, account: account, inbox: inbox, team: team, assignee: assignee)
      message = create(:message, account: account, conversation: conversation, inbox: inbox, content: content)
      attachment = message.attachments.new(account_id: account.id, file_type: :image)
      attachment.file.attach(io: Rails.root.join('spec/assets/sample.png').open, filename: 'sample.png', content_type: 'image/png')
      attachment.save!
      [conversation, message, attachment]
    end

    before { inbox.update!(agent_conversation_isolation: true) }

    it 'hides an attachment from a colleague-owned conversation' do
      _c, _m, foreign = create_owned_attachment(assignee: owner)
      _c2, _m2, mine = create_owned_attachment(assignee: agent)
      ids = builder.deduped_scope.pluck(:id)
      expect(ids).to include(mine.id)
      expect(ids).not_to include(foreign.id)
    end

    it 'keeps an attachment from an unassigned conversation' do
      _c, _m, unassigned = create_owned_attachment(assignee: nil)
      expect(builder.deduped_scope.pluck(:id)).to include(unassigned.id)
    end

    it 'hides a colleague conversation link from links_scope' do
      foreign_conv, foreign_msg, = create_owned_attachment(assignee: owner)
      mine_conv, mine_msg, = create_owned_attachment(assignee: agent)
      ids = builder.links_scope.pluck(:id)
      expect(ids).to include(mine_msg.id)
      expect(ids).not_to include(foreign_msg.id)
      expect(foreign_conv.assignee_id).to eq(owner.id)
      expect(mine_conv.assignee_id).to eq(agent.id)
    end

    it 'keeps everything for an administrator' do
      admin = create(:user, account: account, role: :administrator)
      _c, _m, foreign = create_owned_attachment(assignee: owner)
      admin_builder = described_class.new(user: admin, account: account, filters: { type: 'image' })
      expect(admin_builder.deduped_scope.pluck(:id)).to include(foreign.id)
    end

    # CONVERSA SEM TIME (antes da triagem). Esta regra NAO e isenta do time nulo (fica
    # fora de Inbox::TEAMLESS_EXEMPT_RULES) — e aqui quem responde e o espelho SQL
    # (`exclude_hidden`), nao o guard por-conversa. Se o SQL isentasse, a midia e os links
    # da conversa do colega ainda sem triagem vazariam pela galeria com o guard bloqueando
    # a abertura: as duas superficies discordando, que e o que a regra unica evita.
    it 'STILL hides the attachment of a colleague conversation that has no team yet' do
      _c, _m, foreign = create_owned_attachment(assignee: owner, team: nil)
      _c2, _m2, mine = create_owned_attachment(assignee: agent, team: nil)
      ids = builder.deduped_scope.pluck(:id)
      expect(ids).to include(mine.id)
      expect(ids).not_to include(foreign.id)
    end

    it 'STILL hides the link of a colleague conversation that has no team yet' do
      _c, foreign_msg, = create_owned_attachment(assignee: owner, team: nil)
      expect(builder.links_scope.pluck(:id)).not_to include(foreign_msg.id)
    end
  end
end
