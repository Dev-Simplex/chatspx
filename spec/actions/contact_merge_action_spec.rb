require 'rails_helper'

describe ContactMergeAction do
  subject(:contact_merge) { described_class.new(account: account, base_contact: base_contact, mergee_contact: mergee_contact).perform }

  let!(:account) { create(:account) }
  let!(:base_contact) do
    create(:contact, identifier: 'base_contact', email: 'old@old.com', phone_number: '', custom_attributes: { val_test: 'old', val_empty_old: '' },
                     account: account)
  end
  let!(:mergee_contact) do
    create(:contact, identifier: '', email: 'new@new.com', phone_number: '+12212345',
                     custom_attributes: { val_test: 'new', val_new: 'new', val_empty_new: '' }, account: account)
  end

  before do
    2.times.each do
      create(:conversation, contact: base_contact)
      create(:conversation, contact: mergee_contact)
      create(:message, sender: mergee_contact)
      create(:note, contact: mergee_contact, account: mergee_contact.account)
    end
  end

  describe '#perform' do
    it 'deletes mergee_contact' do
      contact_merge
      expect { mergee_contact.reload }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it 'copies information from mergee contact to base contact' do
      contact_merge
      base_contact.reload
      expect(base_contact.identifier).to eq('base_contact')
      expect(base_contact.email).to eq('old@old.com')
      expect(base_contact.phone_number).to eq('+12212345')
      expect(base_contact.custom_attributes['val_test']).to eq('old')
      expect(base_contact.custom_attributes['val_new']).to eq('new')
      expect(base_contact.custom_attributes['val_empty_old']).to eq('')
      expect(base_contact.custom_attributes['val_empty_new']).to eq('')
    end

    context 'when base contact and merge contact are same' do
      it 'does not delete contact' do
        mergee_contact = base_contact
        contact_merge
        expect(mergee_contact.reload).not_to be_nil
      end
    end

    context 'when mergee contact has conversations' do
      it 'moves the conversations to base contact' do
        contact_merge
        expect(base_contact.conversations.count).to be 4
      end
    end

    context 'when mergee contact has contact inboxes' do
      it 'moves the contact inboxes to base contact' do
        contact_merge
        expect(base_contact.contact_inboxes.count).to be 4
      end
    end

    context 'when mergee contact has messages' do
      it 'moves the messages to base contact' do
        contact_merge
        expect(base_contact.messages.count).to be 2
      end
    end

    context 'when mergee contact has notes' do
      it 'moves the notes to base contact' do
        expect(base_contact.notes.count).to be 0
        expect(mergee_contact.notes.count).to be 2

        contact_merge

        expect(base_contact.reload.notes.count).to be 2
      end
    end

    # O teto de custom_attributes (bloco 1.14) e do CONTATO, e a fusao soma dois
    # contatos. Com 30 + 30 chaves — nenhum dos dois acima do teto de 50 — o
    # `update!` do fim da fusao levantava RecordInvalid e revertia a transacao
    # INTEIRA: o mergee voltava, as conversas nao migravam, e o merge quebrava no
    # painel, na API publica e no resolve_lid_job. A fusao nao pode ser recusada
    # por um teto que nenhum dos dois lados violou: ela poda.
    context 'when the two contacts together blow past the attribute cap' do
      let(:base_attributes) { (1..30).to_h { |index| ["base_#{index}", "valor #{index}"] } }
      let(:mergee_attributes) { (1..30).to_h { |index| ["mergee_#{format('%02d', index)}", "valor #{index}"] } }

      before do
        base_contact.update!(custom_attributes: base_attributes)
        mergee_contact.update!(custom_attributes: mergee_attributes)
      end

      it 'os dois lados estao conformes antes da fusao' do
        expect(base_contact.reload).to be_valid
        expect(mergee_contact.reload).to be_valid
        expect(base_contact.custom_attributes.size + mergee_contact.custom_attributes.size).to eq(60)
      end

      it 'funde sem levantar erro' do
        expect { contact_merge }.not_to raise_error
      end

      it 'nao reverte a fusao: o mergee morre e as conversas migram' do
        contact_merge

        expect { mergee_contact.reload }.to raise_error(ActiveRecord::RecordNotFound)
        expect(base_contact.reload.conversations.count).to be 4
      end

      it 'mantem TODAS as chaves do base e poda o excedente do incorporado' do
        contact_merge
        merged = base_contact.reload.custom_attributes

        expect(merged.size).to eq(50)
        expect(base_attributes.keys - merged.keys).to eq([])
        expect((merged.keys - base_attributes.keys).sort).to eq(mergee_attributes.keys.sort.first(20))
      end
    end

    # A poda tambem e por BYTES: 40 KB + 40 KB nao cabem, e nenhum dos dois lados
    # viola o teto sozinho.
    context 'when the two contacts together blow past the byte cap' do
      let(:heavy_bag) { (1..40).to_h { |index| ["chave_#{index}", 'a' * 1000] } }

      before do
        base_contact.update!(custom_attributes: { 'base_bag' => heavy_bag })
        mergee_contact.update!(custom_attributes: { 'mergee_bag' => heavy_bag })
      end

      it 'funde e mantem o jsonb do base, descartando o que nao cabe' do
        contact_merge
        merged = base_contact.reload.custom_attributes

        expect(merged.keys).to eq(['base_bag'])
        expect(merged.to_json.bytesize).to be <= Contact::CUSTOM_ATTRIBUTES_MAX_BYTES
      end
    end

    # Contato historico que ja passou do teto antes de o teto existir continua
    # sendo um destino valido de fusao — senao um limite novo quebraria o merge
    # de toda a base antiga.
    context 'when the base contact was already above the cap before the validation existed' do
      let(:legacy_attributes) { (1..80).to_h { |index| ["legado_#{index}", "valor #{index}"] } }

      before do
        base_contact.custom_attributes = legacy_attributes
        base_contact.save!(validate: false)
        mergee_contact.update!(custom_attributes: { 'novo' => 'valor' })
      end

      it 'funde sem erro e nao perde as chaves historicas' do
        contact_merge
        merged = base_contact.reload.custom_attributes

        expect(merged.size).to eq(80)
        expect(legacy_attributes.keys - merged.keys).to eq([])
      end
    end

    # O teto por VALOR tem o mesmo problema do teto por quantidade: quem escreveu
    # o valor foi o incorporado, e quem paga pela recusa e a fusao inteira.
    context 'when the mergee carries a value above the per-key limit' do
      before do
        mergee_contact.custom_attributes = { 'bio' => 'a' * 2000 }
        mergee_contact.save!(validate: false)
      end

      it 'funde e descarta so a chave que nao passa' do
        expect { contact_merge }.not_to raise_error
        expect(base_contact.reload.custom_attributes).not_to have_key('bio')
        expect(base_contact.custom_attributes['val_test']).to eq('old')
      end
    end

    # E o contrario: valor historico do proprio contato base nao pode fazer a
    # fusao explodir — nem ser apagado por ela.
    context 'when the base contact carries a legacy value above the per-key limit' do
      before do
        base_contact.custom_attributes = { 'bio' => 'a' * 2000 }
        base_contact.save!(validate: false)
      end

      it 'funde sem erro e preserva o valor historico' do
        expect { contact_merge }.not_to raise_error
        expect(base_contact.reload.custom_attributes['bio'].length).to eq(2000)
        expect(base_contact.custom_attributes['val_new']).to eq('new')
      end
    end

    context 'when contacts belong to a different account' do
      it 'throws an exception' do
        new_account = create(:account)
        expect do
          described_class.new(account: new_account, base_contact: base_contact,
                              mergee_contact: mergee_contact).perform
        end.to raise_error('contact does not belong to the account')
      end
    end
  end
end
