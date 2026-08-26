# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join 'spec/models/concerns/out_of_offisable_shared.rb'
require Rails.root.join 'spec/models/concerns/avatarable_shared.rb'

RSpec.describe Inbox do
  describe 'validations' do
    it { is_expected.to validate_presence_of(:account_id) }
    it { is_expected.to validate_presence_of(:name) }
  end

  describe 'associations' do
    it { is_expected.to belong_to(:account) }

    it { is_expected.to belong_to(:channel) }

    it { is_expected.to have_many(:contact_inboxes).dependent(:destroy_async) }

    it { is_expected.to have_many(:contacts).through(:contact_inboxes) }

    it { is_expected.to have_many(:inbox_members).dependent(:destroy_async) }

    it { is_expected.to have_many(:members).through(:inbox_members).source(:user) }

    it { is_expected.to have_many(:conversations).dependent(:destroy_async) }

    it { is_expected.to have_many(:messages).dependent(:destroy_async) }

    it { is_expected.to have_one(:agent_bot_inbox) }

    it { is_expected.to have_many(:webhooks).dependent(:destroy_async) }

    it { is_expected.to have_many(:reporting_events) }

    it { is_expected.to have_many(:hooks) }
  end

  describe 'concerns' do
    it_behaves_like 'out_of_offisable'
    it_behaves_like 'avatarable'
  end

  describe '#add_members' do
    let(:inbox) { FactoryBot.create(:inbox) }

    before do
      allow(Rails.configuration.dispatcher).to receive(:dispatch)
    end

    it 'handles adds all members and resets cache keys' do
      users = FactoryBot.create_list(:user, 3)
      inbox.add_members(users.map(&:id))
      expect(inbox.reload.inbox_members.size).to eq(3)

      expect(Rails.configuration.dispatcher).to have_received(:dispatch).at_least(:once)
                                                                        .with(
                                                                          'account.cache_invalidated',
                                                                          kind_of(Time),
                                                                          account: inbox.account,
                                                                          cache_keys: inbox.account.cache_keys
                                                                        )
    end
  end

  describe '#remove_members' do
    let(:inbox) { FactoryBot.create(:inbox) }
    let(:users) { FactoryBot.create_list(:user, 3) }

    before do
      inbox.add_members(users.map(&:id))
      allow(Rails.configuration.dispatcher).to receive(:dispatch)
    end

    it 'removes the members and resets cache keys' do
      expect(inbox.reload.inbox_members.size).to eq(3)

      inbox.remove_members(users.map(&:id))
      expect(inbox.reload.inbox_members.size).to eq(0)

      expect(Rails.configuration.dispatcher).to have_received(:dispatch).at_least(:once)
                                                                        .with(
                                                                          'account.cache_invalidated',
                                                                          kind_of(Time),
                                                                          account: inbox.account,
                                                                          cache_keys: inbox.account.cache_keys
                                                                        )
    end
  end

  describe '#assignable_agents' do
    let(:inbox) { FactoryBot.create(:inbox) }
    let(:account) { inbox.account }

    it 'never includes agent bots, only users' do
      agent = create(:user, account: account, role: :agent)
      inbox.add_members([agent.id])
      create(:agent_bot_inbox, inbox: inbox, agent_bot: create(:agent_bot, account: account))
      assistant = create(:captain_assistant, account: account)

      assignable = inbox.reload.assignable_agents

      expect(assignable).to all(be_a(User))
      expect(assignable.map(&:id)).to include(agent.id)
      expect(assignable).not_to include(assistant.reload.agent_bot)
    end
  end

  describe '#facebook?' do
    let(:inbox) do
      FactoryBot.build(:inbox, channel: channel_val)
    end

    context 'when the channel type is Channel::FacebookPage' do
      let(:channel_val) { Channel::FacebookPage.new }

      it do
        expect(inbox.facebook?).to be(true)
        expect(inbox.inbox_type).to eq('Facebook')
      end
    end

    context 'when the channel type is not Channel::FacebookPage' do
      let(:channel_val) { Channel::WebWidget.new }

      it do
        expect(inbox.facebook?).to be(false)
        expect(inbox.inbox_type).to eq('Website')
      end
    end
  end

  describe '#web_widget?' do
    let(:inbox) do
      FactoryBot.build(:inbox, channel: channel_val)
    end

    context 'when the channel type is Channel::WebWidget' do
      let(:channel_val) { Channel::WebWidget.new }

      it do
        expect(inbox.web_widget?).to be(true)
        expect(inbox.inbox_type).to eq('Website')
      end
    end

    context 'when the channel is not Channel::WebWidget' do
      let(:channel_val) { Channel::Api.new }

      it do
        expect(inbox.web_widget?).to be(false)
        expect(inbox.inbox_type).to eq('API')
      end
    end
  end

  describe '#api?' do
    let(:inbox) do
      FactoryBot.build(:inbox, channel: channel_val)
    end

    context 'when the channel type is Channel::Api' do
      let(:channel_val) { Channel::Api.new }

      it do
        expect(inbox.api?).to be(true)
        expect(inbox.inbox_type).to eq('API')
      end
    end

    context 'when the channel is not Channel::Api' do
      let(:channel_val) { Channel::FacebookPage.new }

      it do
        expect(inbox.api?).to be(false)
        expect(inbox.inbox_type).to eq('Facebook')
      end
    end
  end

  describe '#validations' do
    let(:inbox) { FactoryBot.create(:inbox) }

    context 'when validating inbox name' do
      it 'does not allow empty string' do
        inbox.name = ''
        expect(inbox).not_to be_valid
        expect(inbox.errors.full_messages[0]).to eq(
          "Name can't be blank"
        )
      end

      it 'does allow special characters except /\@<> in between' do
        inbox.name = 'inbox-name'
        expect(inbox).to be_valid

        inbox.name = 'inbox_name.and_1'
        expect(inbox).to be_valid
      end

      context 'when special characters allowed for some channel' do
        let!(:tw_channel_val) { FactoryBot.create(:channel_twitter_profile) }
        let(:inbox) { create(:inbox, channel: tw_channel_val) }

        it 'does allow special chacters like /\@<> for Facebook Channel' do
          inbox.name = 'inbox@name'
          expect(inbox).to be_valid
        end
      end
    end
  end

  describe '#update' do
    let!(:inbox) { FactoryBot.create(:inbox) }
    let!(:portal) { FactoryBot.create(:portal) }

    before do
      allow(Rails.configuration.dispatcher).to receive(:dispatch)
    end

    it 'set portal id in inbox' do
      inbox.portal_id = portal.id
      inbox.save

      expect(inbox.portal).to eq(portal)
    end

    it 'sends the inbox_created event if ENABLE_INBOX_EVENTS is true' do
      with_modified_env ENABLE_INBOX_EVENTS: 'true' do
        channel = inbox.channel
        channel.update(widget_color: '#fff')

        expect(Rails.configuration.dispatcher).to have_received(:dispatch)
          .with(
            'inbox.updated',
            kind_of(Time),
            inbox: inbox,
            changed_attributes: kind_of(Object)
          )
      end
    end

    it 'sends the inbox_created event if ENABLE_INBOX_EVENTS is false' do
      channel = inbox.channel
      channel.update(widget_color: '#fff')

      expect(Rails.configuration.dispatcher).not_to have_received(:dispatch)
        .with(
          'inbox.updated',
          kind_of(Time),
          inbox: inbox,
          changed_attributes: kind_of(Object)
        )
    end

    it 'resets cache key if there is an update in the channel' do
      channel = inbox.channel
      channel.update(widget_color: '#fff')

      expect(Rails.configuration.dispatcher).to have_received(:dispatch)
        .with(
          'account.cache_invalidated',
          kind_of(Time),
          account: inbox.account,
          cache_keys: inbox.account.cache_keys
        )
    end

    it 'updates the cache key after update' do
      expect(inbox.account).to receive(:update_cache_key).with('inbox')
      inbox.update(name: 'New Name')
    end

    it 'updates the cache key after touch' do
      expect(inbox.account).to receive(:update_cache_key).with('inbox')
      inbox.touch # rubocop:disable Rails/SkipsModelValidations
    end
  end

  describe '#sanitized_name' do
    context 'when inbox name contains forbidden characters' do
      it 'removes forbidden and spam-trigger characters' do
        inbox = FactoryBot.build(:inbox, name: 'Test/Name\\With<Bad>@Characters"And\';:Quotes!#$%')
        expect(inbox.sanitized_name).to eq('Test/NameWithBadCharactersAnd\'Quotes')
      end
    end

    context 'when inbox name has leading/trailing non-word characters' do
      it 'removes leading and trailing symbols' do
        inbox = FactoryBot.build(:inbox, name: '!!!Test Name***')
        expect(inbox.sanitized_name).to eq('Test Name')
      end

      it 'handles mixed leading/trailing characters' do
        inbox = FactoryBot.build(:inbox, name: '###@@@Test Inbox Name$$$%%')
        expect(inbox.sanitized_name).to eq('Test Inbox Name')
      end
    end

    context 'when inbox name has multiple spaces' do
      it 'normalizes multiple spaces to single space' do
        inbox = FactoryBot.build(:inbox, name: 'Test    Multiple     Spaces')
        expect(inbox.sanitized_name).to eq('Test Multiple Spaces')
      end

      it 'handles tabs and other whitespace' do
        inbox = FactoryBot.build(:inbox, name: "Test\t\nMultiple\r\nSpaces")
        expect(inbox.sanitized_name).to eq('Test Multiple Spaces')
      end
    end

    context 'when inbox name has leading/trailing whitespace' do
      it 'strips whitespace' do
        inbox = FactoryBot.build(:inbox, name: '   Test Name   ')
        expect(inbox.sanitized_name).to eq('Test Name')
      end
    end

    context 'when inbox name becomes empty after sanitization' do
      context 'with email channel' do
        it 'falls back to email local part' do
          email_channel = FactoryBot.build(:channel_email, email: 'support@example.com')
          inbox = FactoryBot.build(:inbox, name: '\\<>@"', channel: email_channel)
          expect(inbox.sanitized_name).to eq('Support')
        end

        it 'handles email with complex local part' do
          email_channel = FactoryBot.build(:channel_email, email: 'help-desk_team@example.com')
          inbox = FactoryBot.build(:inbox, name: '!!!@@@', channel: email_channel)
          expect(inbox.sanitized_name).to eq('Help Desk Team')
        end
      end

      context 'with non-email channel' do
        it 'returns empty string when name becomes blank' do
          web_widget_channel = FactoryBot.build(:channel_widget)
          inbox = FactoryBot.build(:inbox, name: '\\<>@"', channel: web_widget_channel)
          expect(inbox.sanitized_name).to eq('')
        end
      end
    end

    context 'when inbox name is blank initially' do
      context 'with email channel' do
        it 'uses email local part as fallback' do
          email_channel = FactoryBot.build(:channel_email, email: 'customer-care@example.com')
          inbox = FactoryBot.build(:inbox, name: '', channel: email_channel)
          expect(inbox.sanitized_name).to eq('Customer Care')
        end
      end

      context 'with non-email channel' do
        it 'returns empty string' do
          api_channel = FactoryBot.build(:channel_api)
          inbox = FactoryBot.build(:inbox, name: '', channel: api_channel)
          expect(inbox.sanitized_name).to eq('')
        end
      end
    end

    context 'when inbox name contains valid characters' do
      it 'preserves valid characters like hyphens, underscores, and dots' do
        inbox = FactoryBot.build(:inbox, name: 'Test-Name_With.Valid-Characters')
        expect(inbox.sanitized_name).to eq('Test-Name_With.Valid-Characters')
      end

      it 'preserves alphanumeric characters and spaces' do
        inbox = FactoryBot.build(:inbox, name: 'Customer Support 123')
        expect(inbox.sanitized_name).to eq('Customer Support 123')
      end

      it 'preserves balanced safe characters but removes spam-trigger symbols' do
        inbox = FactoryBot.build(:inbox, name: "Test!#$%&'*+/=?^_`{|}~-Name")
        expect(inbox.sanitized_name).to eq("Test'/_-Name")
      end

      it 'keeps commonly used safe characters' do
        inbox = FactoryBot.build(:inbox, name: "Support/Help's Team.Desk_2024-Main")
        expect(inbox.sanitized_name).to eq("Support/Help's Team.Desk_2024-Main")
      end
    end

    context 'when inbox name contains problematic characters for email headers' do
      it 'preserves Unicode symbols (trademark, etc.)' do
        inbox = FactoryBot.build(:inbox, name: 'Test™Name®With©Special™Characters')
        expect(inbox.sanitized_name).to eq('Test™Name®With©Special™Characters')
      end
    end

    context 'with edge cases' do
      it 'handles nil name gracefully' do
        inbox = FactoryBot.build(:inbox)
        allow(inbox).to receive(:name).and_return(nil)
        expect { inbox.sanitized_name }.not_to raise_error
      end

      it 'handles very long names' do
        long_name = 'A' * 1000
        inbox = FactoryBot.build(:inbox, name: long_name)
        expect(inbox.sanitized_name).to eq(long_name)
      end

      it 'handles unicode characters and preserves emojis' do
        inbox = FactoryBot.build(:inbox, name: 'Test Name with émojis 🎉')
        expect(inbox.sanitized_name).to eq('Test Name with émojis 🎉')
      end
    end
  end

  # A lista de times chega da tela por multipart, que nao tem tipo: cada id vem como string e
  # "lista vazia" vem como um item em branco. Sem a normalizacao na escrita o branco viraria 0 e a
  # regra passaria a valer para "o time 0", isto e, para NENHUM time — a regra se desligaria em
  # silencio com a tela mostrando ela LIGADA. Estes exemplos travam esse caminho.
  describe 'normalizacao da lista de times na escrita' do
    let(:account) { create(:account) }
    let(:inbox) { create(:inbox, account: account) }

    Inbox::ISOLATION_RULES.each_value do |list_column|
      context "with #{list_column}" do
        it 'converte id em string para inteiro' do
          inbox.update!(list_column => %w[7 12])
          expect(inbox.reload[list_column]).to eq([7, 12])
        end

        it 'descarta o item em branco que o multipart usa para dizer "lista vazia"' do
          inbox.update!(list_column => [''])
          expect(inbox.reload[list_column]).to eq([])
        end

        it 'descarta zero e lixo, que virariam "time 0" e desligariam a regra em silencio' do
          inbox.update!(list_column => ['0', 'abc', nil, 9])
          expect(inbox.reload[list_column]).to eq([9])
        end

        it 'nao repete time escolhido duas vezes' do
          inbox.update!(list_column => [5, '5', 5])
          expect(inbox.reload[list_column]).to eq([5])
        end
      end
    end

    it 'lista limpa pelo multipart volta a valer para TODOS os times, nao para nenhum' do
      team = create(:team, account: account)
      inbox.update!(team_message_isolation: true, team_message_isolation_team_ids: [team.id])
      expect(inbox.isolation_applies_to_team?(:team_message_isolation, create(:team, account: account).id)).to be(false)

      # e o que a tela manda quando o admin remove todos os chips
      inbox.update!(team_message_isolation_team_ids: [''])
      expect(inbox.isolation_applies_to_team?(:team_message_isolation, create(:team, account: account).id)).to be(true)
    end
  end

  # ESCOPO POR TIME DAS 3 REGRAS DE ISOLAMENTO — a matriz da regra, no unico lugar
  # onde ela existe. Os 7 pontos de aplicacao sao testados em
  # spec/services/isolation_team_scope_spec.rb; aqui e a regra pura.
  describe '#isolation_applies_to_team?' do
    let(:account) { create(:account) }
    let(:inbox) { create(:inbox, account: account) }
    let(:team) { create(:team, account: account) }
    let(:other_team) { create(:team, account: account) }

    Inbox::ISOLATION_RULES.each_key do |rule|
      context "with the #{rule} rule" do
        let(:list_column) { Inbox::ISOLATION_RULES.fetch(rule) }

        it 'is false when the flag is off, whatever the list says' do
          inbox.update!(rule => false, list_column => [team.id])
          expect(inbox.isolation_applies_to_team?(rule, team.id)).to be(false)
        end

        # RETROCOMPAT: e o estado de TODA caixa ja configurada no dia do deploy.
        it 'is true for any team when the list is empty' do
          inbox.update!(rule => true, list_column => [])
          expect(inbox.isolation_applies_to_team?(rule, team.id)).to be(true)
          expect(inbox.isolation_applies_to_team?(rule, other_team.id)).to be(true)
        end

        it 'is true for a team inside the chosen list' do
          inbox.update!(rule => true, list_column => [team.id])
          expect(inbox.isolation_applies_to_team?(rule, team.id)).to be(true)
        end

        it 'is false for a team outside the chosen list' do
          inbox.update!(rule => true, list_column => [team.id])
          expect(inbox.isolation_applies_to_team?(rule, other_team.id)).to be(false)
        end

        # Conversa SEM time com a lista JA restrita: as familias se separam AQUI, nao so no
        # caso da lista vazia. Nas 2 regras de MENSAGEM a regra nao alcanca (mostrar as bolhas
        # de quem ainda nao passou pela triagem). Em agent_conversation_isolation ela ALCANCA:
        # "sem time" nao e um time que o admin excluiu, e se restringir o escopo abrisse a
        # conversa sem time do colega, apertar a regra AFROUXARIA o acesso — o oposto do que
        # a tela promete.
        it 'follows the rule family for a conversation without a team once the list is restricted' do
          inbox.update!(rule => true, list_column => [team.id])
          esperado = Inbox::TEAMLESS_EXEMPT_RULES.exclude?(rule)
          expect(inbox.isolation_applies_to_team?(rule, nil)).to be(esperado)
        end

        it 'accepts the team id as a string' do
          inbox.update!(rule => true, list_column => [team.id])
          expect(inbox.isolation_applies_to_team?(rule, team.id.to_s)).to be(true)
        end
      end
    end

    # A DISTINCAO QUE O ESCOPO POR TIME NAO PODE APAGAR — conversa SEM time com a lista
    # VAZIA (o estado de TODA caixa ja configurada no dia do deploy).
    #
    # As duas regras de MENSAGEM sao isentas (Inbox::TEAMLESS_EXEMPT_RULES): a conversa
    # nasce sem time, antes da triagem, e esconder as bolhas dela esconderia o lead novo.
    # `agent_conversation_isolation` NAO e isenta: ali o criterio de fechamento nao e o
    # time, e sim "esta atribuida a outra pessoa". Se ela virasse isenta, o deploy desta
    # feature ABRIRIA para todo agente a conversa do colega ainda sem triagem — regressao
    # de seguranca, nao o relaxamento que o admin pediu.
    context 'with a conversation that has no team yet and an empty list' do
      before do
        inbox.update!(
          team_message_isolation: true,
          agent_message_isolation: true,
          agent_conversation_isolation: true
        )
      end

      it 'exempts the two MESSAGE rules so the untriaged lead stays readable' do
        expect(inbox.isolation_applies_to_team?(:team_message_isolation, nil)).to be(false)
        expect(inbox.isolation_applies_to_team?(:agent_message_isolation, nil)).to be(false)
      end

      it 'keeps agent_conversation_isolation applying (it closes by owner, not by team)' do
        expect(inbox.isolation_applies_to_team?(:agent_conversation_isolation, nil)).to be(true)
      end

      it 'lists exactly the two message rules as teamless-exempt' do
        expect(Inbox::TEAMLESS_EXEMPT_RULES).to contain_exactly(:team_message_isolation, :agent_message_isolation)
      end
    end

    it 'defaults every list to empty so no configured inbox changes on deploy' do
      expect(inbox.team_message_isolation_team_ids).to eq([])
      expect(inbox.agent_message_isolation_team_ids).to eq([])
      expect(inbox.agent_conversation_isolation_team_ids).to eq([])
    end

    it 'raises on an unknown rule instead of silently answering "does not isolate"' do
      expect { inbox.isolation_applies_to_team?(:nope, team.id) }.to raise_error(KeyError)
    end
  end

  describe '.isolation_applies_sql' do
    it 'raises on an unknown rule' do
      expect { described_class.isolation_applies_sql(:nope) }.to raise_error(KeyError)
    end

    # O SQL e o espelho da regra Ruby; se os dois divergirem, a listagem esconde o que a
    # conversa aberta mostra (ou o contrario). Aqui so garantimos que ele RODA e concorda
    # com o helper nos 3 casos que mais importam.
    it 'agrees with the ruby helper for empty list / chosen team / other team' do
      account = create(:account)
      inbox = create(:inbox, account: account, agent_message_isolation: true)
      team = create(:team, account: account)
      other_team = create(:team, account: account)
      chosen = create(:conversation, account: account, inbox: inbox, team: team)
      outside = create(:conversation, account: account, inbox: inbox, team: other_team)
      teamless = create(:conversation, account: account, inbox: inbox, team: nil)

      matching = lambda {
        Conversation.joins(:inbox)
                    .where(id: [chosen.id, outside.id, teamless.id])
                    .where(described_class.isolation_applies_sql(:agent_message_isolation))
                    .pluck(:id)
      }

      expect(matching.call).to contain_exactly(chosen.id, outside.id)

      inbox.update!(agent_message_isolation_team_ids: [team.id])
      expect(matching.call).to contain_exactly(chosen.id)
    end

    # O SQL espelha a EXCECAO do time nulo, nao a inverte: se ele isentasse a conversa sem
    # time tambem em agent_conversation_isolation, a galeria / o download em massa / o
    # bulk passariam a entregar a conversa do colega ainda sem triagem — exatamente o
    # vazamento que TEAMLESS_EXEMPT_RULES existe para nao abrir.
    it 'keeps the teamless conversation inside agent_conversation_isolation with an empty list' do
      account = create(:account)
      inbox = create(:inbox, account: account, agent_message_isolation: true, agent_conversation_isolation: true)
      team = create(:team, account: account)
      with_team = create(:conversation, account: account, inbox: inbox, team: team)
      teamless = create(:conversation, account: account, inbox: inbox, team: nil)

      matching = lambda { |rule|
        Conversation.joins(:inbox)
                    .where(id: [with_team.id, teamless.id])
                    .where(described_class.isolation_applies_sql(rule))
                    .pluck(:id)
      }

      expect(matching.call(:agent_message_isolation)).to contain_exactly(with_team.id)
      expect(matching.call(:agent_conversation_isolation)).to contain_exactly(with_team.id, teamless.id)
    end

    # E o Ruby e o SQL tem que responder a MESMA coisa nesse ponto — divergir aqui e como
    # a lista passa a esconder o que a conversa aberta mostra (ou o contrario).
    it 'agrees with the ruby helper on the teamless conversation, rule by rule' do
      account = create(:account)
      inbox = create(:inbox, account: account)
      Inbox::ISOLATION_RULES.each_key { |rule| inbox.update!(rule => true) }
      teamless = create(:conversation, account: account, inbox: inbox, team: nil)

      Inbox::ISOLATION_RULES.each_key do |rule|
        in_sql = Conversation.joins(:inbox).where(id: teamless.id)
                             .where(described_class.isolation_applies_sql(rule)).exists?
        expect(in_sql).to be(inbox.isolation_applies_to_team?(rule, nil))
      end
    end
  end
end
