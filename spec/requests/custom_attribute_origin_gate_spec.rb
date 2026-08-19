require 'rails_helper'

# Bloco 4.17 — o aceite, medido pelo endpoint real: atributo que exige origem verificada,
# escrito sem credencial, NAO altera o valor, e a tentativa fica registrada.
#
# O endpoint escolhido e o de CONVERSA de proposito: e a superficie onde o site escreve com
# mais liberdade — `widget/conversations#set_custom_attributes` nao tem assinatura nenhuma.
RSpec.describe 'portao de origem nos atributos', type: :request do
  let(:account) { create(:account) }
  let(:web_widget) { create(:channel_widget, account: account) }
  let(:inbox) { web_widget.inbox }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, hmac_verified: false) }
  let!(:conversation) do
    create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox,
                          custom_attributes: { 'cpf' => '111.111.111-11', 'carrinho_valor' => 10 })
  end
  let(:token) do
    Widget::TokenService.new(payload: { source_id: contact_inbox.source_id, inbox_id: inbox.id }).generate_token
  end

  let!(:protegida) do
    create(:custom_attribute_definition, account: account, attribute_key: 'cpf',
                                         attribute_model: 'conversation_attribute',
                                         attribute_display_type: 'text', requires_verified_origin: true)
  end

  def write(attrs)
    post '/api/v1/widget/conversations/set_custom_attributes',
         params: { website_token: web_widget.website_token, custom_attributes: attrs },
         headers: { 'X-Auth-Token' => token },
         as: :json
  end

  context 'when a sessao nao tem origem verificada' do
    it 'NAO altera o valor do atributo protegido' do
      write({ cpf: '999.999.999-99' })

      expect(response).to have_http_status(:success)
      expect(conversation.reload.custom_attributes['cpf']).to eq('111.111.111-11')
    end

    it 'registra a tentativa' do
      allow(Rails.logger).to receive(:warn)

      write({ cpf: '999.999.999-99' })

      expect(Rails.logger).to have_received(:warn)
        .with(/escrita recusada por origem nao verificada account_id=#{account.id} .*chaves=cpf/)
    end

    it 'grava as chaves nao protegidas do mesmo payload' do
      write({ cpf: '999.999.999-99', carrinho_valor: 4200 })

      atributos = conversation.reload.custom_attributes
      expect(atributos['carrinho_valor']).to eq(4200)
      expect(atributos['cpf']).to eq('111.111.111-11')
    end

    it 'nao cria definicao para a chave que recusou' do
      write({ cpf: '999.999.999-99', cupom: 'BLACK' })

      chaves = account.custom_attribute_definitions.where(attribute_model: 'conversation_attribute').pluck(:attribute_key)
      expect(chaves).to contain_exactly('cpf', 'cupom')
      expect(protegida.reload.origin).to be_nil
    end

    # Omitir a chave protegida nao pode ser a porta dos fundos para apaga-la: apagar
    # tambem e alterar. A substituicao continua valendo para tudo que nao e protegido.
    it 'NAO apaga o atributo protegido quando ele e omitido do payload' do
      write({ carrinho_valor: 4200 })

      atributos = conversation.reload.custom_attributes
      expect(atributos).to eq({ 'carrinho_valor' => 4200, 'cpf' => '111.111.111-11' })
    end

    it 'continua removendo a chave NAO protegida que saiu do payload' do
      write({ cupom: 'BLACK' })

      atributos = conversation.reload.custom_attributes
      expect(atributos).to eq({ 'cupom' => 'BLACK', 'cpf' => '111.111.111-11' })
    end
  end

  context 'when a sessao tem origem verificada' do
    let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, hmac_verified: true) }

    it 'altera o valor do atributo protegido' do
      write({ cpf: '999.999.999-99' })

      expect(response).to have_http_status(:success)
      expect(conversation.reload.custom_attributes['cpf']).to eq('999.999.999-99')
    end
  end

  context 'when nenhuma definicao exige origem verificada' do
    it 'grava normalmente — nil na coluna e o comportamento de hoje' do
      protegida.update!(requires_verified_origin: nil)

      write({ cpf: '999.999.999-99' })

      expect(conversation.reload.custom_attributes['cpf']).to eq('999.999.999-99')
    end
  end
end
