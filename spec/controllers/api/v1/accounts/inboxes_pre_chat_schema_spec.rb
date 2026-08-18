# frozen_string_literal: true

require 'rails_helper'

# Mecanismo do aceite do bloco 3.12 (Onda 2), lado STRONG PARAMS.
#
# `Channel::WebWidget::EDITABLE_ATTRS` e uma lista fechada: chave nao declarada
# nao levanta erro, ela e DESCARTADA em silencio. Sem este arquivo, "a tela
# grava a mascara" e afirmacao — o campo sobe no PATCH, o Rails joga fora e a
# resposta volta 200 como se tivesse gravado.
RSpec.describe 'Inboxes API — pre-chat com mascara, condicional e etapa', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:widget) { create(:channel_widget, account: account) }
  let(:inbox) { create(:inbox, account: account, channel: widget) }

  def patch_pre_chat(fields, extra = {})
    patch "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}",
          headers: admin.create_new_auth_token,
          params: {
            channel: {
              pre_chat_form_enabled: true,
              pre_chat_form_options: { pre_chat_message: 'Oi', pre_chat_fields: fields }.merge(extra)
            }
          },
          as: :json
  end

  def a_field(extra = {})
    { field_type: 'standard', name: 'cpf', label: 'CPF', type: 'text', enabled: true }.merge(extra)
  end

  it 'grava mask, validator, step, position, help_text, error_message e show_if — nao descarta nenhum' do
    patch_pre_chat(
      [
        {
          field_type: 'standard', name: 'fullName', label: 'Nome', type: 'text',
          enabled: true, required: true, step: 1, position: 0, validator: 'junk_name'
        },
        {
          field_type: 'standard', name: 'cpf', label: 'CPF', type: 'text',
          enabled: true, required: true,
          mask: 'cpf', validator: 'cpf', step: 2, position: 1,
          help_text: 'Usamos para localizar seu cadastro',
          error_message: 'Confira o CPF digitado',
          show_if: { field: 'fullName', operator: 'filled' }
        }
      ]
    )

    expect(response).to have_http_status(:success)

    saved = widget.reload.pre_chat_form_options['pre_chat_fields']
    expect(saved[0]).to include('validator' => 'junk_name', 'step' => 1, 'position' => 0)
    expect(saved[1]).to include(
      'mask' => 'cpf',
      'validator' => 'cpf',
      'step' => 2,
      'position' => 1,
      'help_text' => 'Usamos para localizar seu cadastro',
      'error_message' => 'Confira o CPF digitado',
      'show_if' => { 'field' => 'fullName', 'operator' => 'filled' }
    )
  end

  it 'devolve 422 quando a mascara nao existe, em vez de gravar lixo' do
    patch_pre_chat([{ field_type: 'standard', name: 'cpf', label: 'CPF', type: 'text', enabled: true, mask: 'banana' }])

    expect(response).to have_http_status(:unprocessable_entity)
    expect(widget.reload.pre_chat_form_options['pre_chat_fields'].first['mask']).to be_nil
  end

  it 'grava o modo escolhido — sem ele a tela teria de adivinhar a intencao pelo conteudo' do
    patch_pre_chat([a_field], mode: 'builder')

    expect(response).to have_http_status(:success)
    expect(widget.reload.pre_chat_form_options['mode']).to eq('builder')
  end

  it 'devolve 422 para modo que nao existe' do
    patch_pre_chat([a_field], mode: 'avancado')

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'devolve 422 quando a condicional vem sem operador' do
    patch_pre_chat(
      [{ field_type: 'standard', name: 'cpf', label: 'CPF', type: 'text', enabled: true, show_if: { field: 'fullName' } }]
    )

    expect(response).to have_http_status(:unprocessable_entity)
  end
end
