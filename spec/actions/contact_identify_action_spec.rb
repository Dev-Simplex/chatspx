require 'rails_helper'

describe ContactIdentifyAction do
  # CONTRATO: `Avatar::AvatarFromUrlJob#perform(avatarable_type, avatarable_id, avatar_url)` —
  # NOME DA CLASSE + ID + url, nunca o registro. Os 10 chamadores do codigo usam essa forma; so
  # este spec ficou na antiga (`(contact, url)`).
  #
  # As assercoes POSITIVAS falhavam, o que era o sinal. As NEGATIVAS
  # (`not_to receive(:perform_later).with(contact, url)`) passavam sem verificar nada: o job ERA
  # chamado, apenas com outros argumentos — entao "nao recebeu COM ESSES argumentos" era verdade
  # por acidente. Tres exemplos verdes que nao provavam o que diziam.
  subject(:contact_identify) { described_class.new(contact: contact, params: params).perform }

  let!(:account) { create(:account) }
  let(:custom_attributes) { { test: 'test', test1: 'test1' } }
  let!(:contact) { create(:contact, account: account, custom_attributes: custom_attributes) }
  let(:params) do
    { name: 'test', identifier: 'test_id', additional_attributes: { location: 'Bengaulru', company_name: 'Meta' },
      custom_attributes: { test: 'new test', test2: 'test2' } }
  end

  describe '#perform' do
    it 'updates the contact' do
      expect(Avatar::AvatarFromUrlJob).not_to receive(:perform_later)
        .with(contact.class.name, contact.id, params[:avatar_url])
      contact_identify
      expect(contact.reload.name).to eq 'test'
      # custom attributes are merged properly without overwriting existing ones
      expect(contact.custom_attributes).to eq({ 'test' => 'new test', 'test1' => 'test1', 'test2' => 'test2' })
      expect(contact.additional_attributes).to eq({ 'company_name' => 'Meta', 'location' => 'Bengaulru' })
      expect(contact.reload.identifier).to eq 'test_id'
    end

    it 'will not call avatar job if avatar is already attached' do
      contact.avatar.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'avatar.png', content_type: 'image/png')
      expect(Avatar::AvatarFromUrlJob).not_to receive(:perform_later)
        .with(contact.class.name, contact.id, params[:avatar_url])
      contact_identify
    end

    it 'merge deeply nested additional attributes' do
      create(:contact, account: account, identifier: '', email: 'test@test.com',
                       additional_attributes: { location: 'Bengaulru', company_name: 'Meta', social_profiles: { linkedin: 'saras' } })
      params = { email: 'test@test.com', additional_attributes: { social_profiles: { twitter: 'saras' } } }
      result = described_class.new(contact: contact, params: params).perform
      expect(result.additional_attributes['social_profiles']).to eq({ 'linkedin' => 'saras', 'twitter' => 'saras' })
    end

    it 'enqueues avatar job when valid avatar url parameter is passed' do
      params = { name: 'test', avatar_url: 'https://chatwoot-assets.local/sample.png' }
      expect(Avatar::AvatarFromUrlJob).to receive(:perform_later)
        .with(contact.class.name, contact.id, params[:avatar_url]).once
      described_class.new(contact: contact, params: params).perform
    end

    it 'does not enqueue avatar job when invalid avatar url parameter is passed' do
      params = { name: 'test', avatar_url: 'invalid-url' }
      expect(Avatar::AvatarFromUrlJob).not_to receive(:perform_later)
      described_class.new(contact: contact, params: params).perform
    end

    context 'when contact with same identifier exists' do
      it 'merges the current contact to identified contact' do
        existing_identified_contact = create(:contact, account: account, identifier: 'test_id')
        result = contact_identify
        expect(result.id).to eq existing_identified_contact.id
        expect(result.name).to eq params[:name]
        expect { contact.reload }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context 'when contact with same email exists' do
      it 'merges the current contact to email contact' do
        existing_email_contact = create(:contact, account: account, email: 'test@test.com', name: 'old name')
        params = { name: 'new name', email: 'test@test.com' }
        result = described_class.new(contact: contact, params: params).perform
        expect(result.id).to eq existing_email_contact.id
        expect(result.name).to eq 'new name'
        expect { contact.reload }.to raise_error(ActiveRecord::RecordNotFound)
      end

      it 'will not merge the current contact to email contact if identifier of email contact is different' do
        existing_email_contact = create(:contact, account: account, identifier: '1', email: 'test@test.com')
        params = { identifier: '2', email: 'test@test.com' }
        result = described_class.new(contact: contact, params: params).perform
        expect(result.id).not_to eq existing_email_contact.id
        expect(result.identifier).to eq params[:identifier]
        expect(result.email).to be_nil
      end
    end

    context 'when contact with same phone_number exists' do
      it 'merges the current contact to phone_number contact' do
        existing_phone_number_contact = create(:contact, account: account, phone_number: '+919999888877')
        params = { phone_number: '+919999888877' }
        result = described_class.new(contact: contact, params: params).perform
        expect(result.id).to eq existing_phone_number_contact.id
        expect(result.name).to eq existing_phone_number_contact.name
        expect { contact.reload }.to raise_error(ActiveRecord::RecordNotFound)
      end

      it 'will not merge the current contact to phone contact if identifier of phone contact is different' do
        existing_phone_number_contact = create(:contact, account: account, identifier: '1', phone_number: '+919999888877')
        params = { identifier: '2', phone_number: '+919999888877' }
        result = described_class.new(contact: contact, params: params).perform
        expect(result.id).not_to eq existing_phone_number_contact.id
        expect(result.identifier).to eq params[:identifier]
        expect(result.email).to be_nil
      end

      it 'will not overide the phone contacts email when params contains different email' do
        existing_phone_number_contact = create(:contact, account: account, email: '1@test.com', phone_number: '+919999888877')
        params = { email: '2@test.com', phone_number: '+919999888877' }
        result = described_class.new(contact: contact, params: params).perform
        expect(result.id).not_to eq existing_phone_number_contact.id
        expect(result.email).to eq params[:email]
        expect(result.phone_number).to be_nil
      end
    end

    context 'when contacts with blank identifiers exist and identify action is called with blank identifier' do
      it 'updates the attributes of contact passed in to identify action' do
        create(:contact, account: account, identifier: '')
        params = { identifier: '', name: 'new name' }
        result = described_class.new(contact: contact, params: params).perform
        expect(result.id).to eq contact.id
        expect(result.name).to eq 'new name'
      end
    end

    context 'when retain_original_contact_name is set to true' do
      it 'will not update the name of the existing contact' do
        existing_email_contact = create(:contact, account: account, name: 'old name', email: 'test@test.com')
        params = { email: 'test@test.com', name: 'new name' }
        result = described_class.new(contact: contact, params: params, retain_original_contact_name: true).perform
        expect(result.id).to eq existing_email_contact.id
        expect(result.name).to eq 'old name'
        expect { contact.reload }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context 'when discard_invalid_attrs is set to false' do
      it 'will not update the name of the existing contact' do
        params = { email: 'blah blah blah', name: 'new name' }
        expect do
          described_class.new(contact: contact, params: params, retain_original_contact_name: true).perform
        end.to raise_error(ActiveRecord::RecordInvalid)
      end
    end

    context 'when discard_invalid_attrs is set to true' do
      it 'will not update the name of the existing contact' do
        params = { phone_number: 'blahblah blah', name: 'new name' }
        described_class.new(contact: contact, params: params, discard_invalid_attrs: true).perform
        expect(contact.reload.name).to eq 'new name'
        expect(contact.phone_number).to be_nil
      end
    end

    context 'when params have not changed' do
      it 'skips save and does not issue an UPDATE query' do
        contact.update!(name: 'test', identifier: 'test_id', custom_attributes: { test: 'test', test1: 'test1' })
        params = { name: 'test', identifier: 'test_id', custom_attributes: { test: 'test', test1: 'test1' } }

        # any_instance is needed because merge lookup can reassign @contact to a different Ruby object
        expect_any_instance_of(Contact).not_to receive(:save!) # rubocop:disable RSpec/AnyInstance
        described_class.new(contact: contact, params: params).perform
      end

      it 'still enqueues avatar job even when attributes have not changed' do
        contact.update!(name: 'test')
        params = { name: 'test', avatar_url: 'https://chatwoot-assets.local/sample.png' }

        expect(Avatar::AvatarFromUrlJob).to receive(:perform_later)
          .with(contact.class.name, contact.id, params[:avatar_url]).once
        described_class.new(contact: contact, params: params).perform
      end
    end
  end

  # B6: chave nova mandada pelo site via setUser/prechat era gravada no jsonb do
  # contato e nao aparecia em lugar nenhum — o painel itera sobre as definicoes
  # (CustomAttributes.vue:76-89) e o filtro recusa chave sem definicao
  # (filters/filter_helper.rb:22-25).
  describe 'auto-provisionamento de CustomAttributeDefinition' do
    let(:contact) { create(:contact, account: account) }

    def definitions
      account.custom_attribute_definitions.where(attribute_model: 'contact_attribute')
    end

    it 'cria a definicao da chave nova' do
      expect do
        described_class.new(contact: contact, params: { custom_attributes: { carrinho_valor: 4200 } }).perform
      end.to change(definitions, :count).by(1)

      definition = definitions.find_by(attribute_key: 'carrinho_valor')
      expect(definition.attribute_display_type).to eq('number')
      expect(definition.attribute_display_name).to eq('Carrinho valor')
    end

    it 'nao duplica quando a mesma chave volta' do
      2.times do |index|
        described_class.new(contact: contact.reload, params: { custom_attributes: { carrinho_valor: 4200 + index } }).perform
      end

      expect(definitions.where(attribute_key: 'carrinho_valor').count).to eq(1)
    end

    it 'nao levanta nem cria definicao para chave reservada' do
      expect do
        described_class.new(contact: contact, params: { custom_attributes: { city: 'Sao Paulo', email: 'x@y.com' } }).perform
      end.not_to change(definitions, :count)
    end

    it 'nao mexe em nada quando a chamada nao traz custom_attributes' do
      expect do
        described_class.new(contact: contact, params: { name: 'Sem atributos' }).perform
      end.not_to change(definitions, :count)
    end
  end

  # Bloco 5.17 — a SUBSTITUICAO de verdade do verbo `set…` (T-I3.8).
  #
  # Ate aqui "setUser SUBSTITUI" era so um comentario. O cliente montava o payload com as chaves
  # ausentes em `undefined`, `JSON.stringify` as descartava, e o que chegava aqui era
  # indistinguivel de um `updateUser`. Mesmo se `nil` chegasse, o `reject(&:blank?)` de
  # `update_contact` o descartaria. `clear_attributes` e o pedido NOMEADO que sobrevive aos dois.
  describe 'clear_attributes — o verbo set apaga o que o site nao mandou' do
    let!(:contact) do
      create(:contact, account: account, name: 'Ana', email: 'ana@exemplo.com.br',
                       phone_number: '+5511999998888', identifier: 'id-1')
    end

    it 'apaga os campos nomeados e preserva os que a chamada trouxe' do
      described_class.new(
        contact: contact,
        params: { identifier: 'id-1', name: 'Ana Maria', clear_attributes: %w[email phone_number] }
      ).perform

      contact.reload
      expect(contact.name).to eq 'Ana Maria'
      expect(contact.email).to be_nil
      expect(contact.phone_number).to be_nil
      # A identidade sobrevive: apagar contato nao e desidentificar sessao.
      expect(contact.identifier).to eq 'id-1'
    end

    it 'nao apaga o campo que a MESMA chamada mandou preenchido' do
      # Ordem nao pode ser contrato: `params` vence a lista, sempre.
      described_class.new(
        contact: contact,
        params: { identifier: 'id-1', email: 'nova@exemplo.com.br', clear_attributes: %w[email] }
      ).perform

      expect(contact.reload.email).to eq 'nova@exemplo.com.br'
    end

    it 'name apagado vira string vazia, nao nil — o resto do produto trata name como string' do
      described_class.new(contact: contact, params: { identifier: 'id-1', clear_attributes: %w[name] }).perform

      expect(contact.reload.name).to eq ''
    end

    it 'RECUSA apagar identifier, mesmo pedido explicitamente' do
      # Apagar o identificador desamarraria o contato da identidade declarada pelo site: a sessao
      # seguinte nao o reencontraria e o visitante viraria cadastro novo, em silencio.
      described_class.new(contact: contact, params: { identifier: 'id-1', clear_attributes: %w[identifier] }).perform

      expect(contact.reload.identifier).to eq 'id-1'
    end

    it 'ignora nome de coluna que nao esta na lista fechada' do
      described_class.new(
        contact: contact,
        params: { identifier: 'id-1', clear_attributes: %w[account_id contact_type blocked avatar_url] }
      ).perform

      contact.reload
      expect(contact.account_id).to eq account.id
      expect(contact.contact_type).to eq 'lead'
      expect(contact.blocked).to be false
    end

    it 'sem clear_attributes nada e apagado — o verbo update segue mesclando' do
      described_class.new(contact: contact, params: { identifier: 'id-1', name: 'Ana Maria' }).perform

      contact.reload
      expect(contact.name).to eq 'Ana Maria'
      expect(contact.email).to eq 'ana@exemplo.com.br'
      expect(contact.phone_number).to eq '+5511999998888'
    end

    it 'lista vazia e o mesmo que ausencia' do
      described_class.new(contact: contact, params: { identifier: 'id-1', clear_attributes: [] }).perform

      expect(contact.reload.email).to eq 'ana@exemplo.com.br'
    end

    # A TRAVA QUE IMPORTA, e ela nao e teorica.
    #
    # Sob `identity_enforcement` estrito, `refuse_merge_under_enforcement?` tira a chave de
    # `@attributes_to_update` para que a sessao nao REIVINDIQUE o e-mail de outro cadastro. Sem a
    # interseccao com essa lista, a mesma sessao que tem a fusao recusada conseguiria APAGAR o
    # e-mail do dono — a recusa protegeria a leitura e deixaria passar a escrita destrutiva, que e
    # pior do que nao ter recusa nenhuma.
    it 'nao apaga o campo cuja fusao foi RECUSADA pelo enforcement estrito' do
      dona = create(:contact, account: account, email: 'dona@exemplo.com.br', name: 'Dona')
      sessao = create(:contact, account: account)

      described_class.new(
        contact: sessao,
        params: { email: 'dona@exemplo.com.br', clear_attributes: %w[email] },
        identity_enforcement: 'strict'
      ).perform

      expect(dona.reload.email).to eq 'dona@exemplo.com.br'
    end
  end
end
