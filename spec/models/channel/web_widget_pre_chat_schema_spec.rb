# frozen_string_literal: true

require 'rails_helper'

# Mecanismo do aceite do bloco 3.12 (Onda 2): "Campo com `mask` e `show_if`
# persiste; forma invalida e rejeitada".
#
# O lado do strong params (o que o `permit` deixa entrar) e coberto por
# `spec/controllers/api/v1/accounts/inboxes_pre_chat_schema_spec.rb`. Aqui e o
# lado do MODELO: o que o JSON Schema aceita e o que ele recusa.
RSpec.describe Channel::WebWidget do
  let(:account) { create(:account) }

  def build_widget(fields)
    described_class.new(
      account: account,
      website_url: 'https://exemplo.com.br',
      pre_chat_form_options: { 'pre_chat_message' => 'Oi', 'pre_chat_fields' => fields }
    )
  end

  def base_field(extra = {})
    {
      'field_type' => 'standard', 'label' => 'CPF', 'name' => 'cpf',
      'type' => 'text', 'required' => true, 'enabled' => true
    }.merge(extra)
  end

  describe 'as sete chaves novas do pre-chat' do
    it 'aceita e persiste mask, validator, step, position, show_if, help_text e error_message' do
      widget = build_widget(
        [
          base_field('step' => 1, 'position' => 0),
          base_field(
            'name' => 'cnpj', 'label' => 'CNPJ',
            'mask' => 'cnpj', 'validator' => 'cnpj', 'step' => 2, 'position' => 1,
            'help_text' => 'Somente numeros', 'error_message' => 'CNPJ invalido',
            'show_if' => { 'field' => 'cpf', 'operator' => 'filled' }
          )
        ]
      )

      expect(widget).to be_valid
      widget.save!

      saved = widget.reload.pre_chat_form_options['pre_chat_fields'][1]
      expect(saved).to include(
        'mask' => 'cnpj',
        'validator' => 'cnpj',
        'step' => 2,
        'position' => 1,
        'help_text' => 'Somente numeros',
        'error_message' => 'CNPJ invalido',
        'show_if' => { 'field' => 'cpf', 'operator' => 'filled' }
      )
    end
  end

  describe 'forma invalida' do
    it 'recusa mascara que nao existe' do
      widget = build_widget([base_field('mask' => 'banana')])

      expect(widget).not_to be_valid
      expect(widget.errors[:pre_chat_form_options].join).to include('mask')
    end

    it 'recusa validador que nao existe' do
      widget = build_widget([base_field('validator' => 'rg')])

      expect(widget).not_to be_valid
      expect(widget.errors[:pre_chat_form_options].join).to include('validator')
    end

    it 'recusa etapa 0 e etapa 9 — o teto de campos e 8, entao o de etapas tambem' do
      expect(build_widget([base_field('step' => 0)])).not_to be_valid
      expect(build_widget([base_field('step' => 9)])).not_to be_valid
      expect(build_widget([base_field('step' => 8)])).to be_valid
    end

    it 'recusa posicao negativa' do
      widget = build_widget([base_field('position' => -1)])

      expect(widget).not_to be_valid
      expect(widget.errors[:pre_chat_form_options].join).to include('position')
    end

    it 'recusa condicional sem operador' do
      widget = build_widget([base_field('show_if' => { 'field' => 'cpf' })])

      expect(widget).not_to be_valid
      expect(widget.errors[:pre_chat_form_options].join).to include('show_if')
    end

    it 'recusa operador de condicional fora dos quatro previstos' do
      widget = build_widget([base_field('show_if' => { 'field' => 'cpf', 'operator' => 'regex', 'value' => 'x' })])

      expect(widget).not_to be_valid
      expect(widget.errors[:pre_chat_form_options].join).to include('operator')
    end

    # A outra ponta desta assercao esta em
    # `prechat/preChatModel.js#updateField`, que APAGA a chave em vez de gravar
    # `null` quando o administrador clica em "Sempre mostrar". Sem as duas, a
    # operacao mais banal do editor de condicional voltaria 422.
    it 'recusa show_if nulo — remover a condicional apaga a chave, nao grava null' do
      widget = build_widget([base_field('show_if' => nil)])

      expect(widget).not_to be_valid
      expect(widget.errors[:pre_chat_form_options].join).to include('show_if')
    end

    it 'recusa chave desconhecida dentro da condicional' do
      widget = build_widget([base_field('show_if' => { 'field' => 'cpf', 'operator' => 'is', 'value' => 'x', 'and' => [] })])

      expect(widget).not_to be_valid
    end

    it 'recusa texto de ajuda acima do teto de 160 caracteres' do
      widget = build_widget([base_field('help_text' => 'a' * 161)])

      expect(widget).not_to be_valid
      expect(widget.errors[:pre_chat_form_options].join).to include('help_text')
    end
  end

  describe 'o modo do formulario (bloco 3.14)' do
    def widget_with_mode(mode)
      described_class.new(
        account: account,
        website_url: 'https://exemplo.com.br',
        pre_chat_form_options: { 'mode' => mode, 'pre_chat_fields' => [base_field] }
      )
    end

    it 'aceita os tres modos previstos' do
      %w[simple builder flow].each do |mode|
        expect(widget_with_mode(mode)).to be_valid
      end
    end

    it 'recusa modo fora do enum' do
      widget = widget_with_mode('avancado')

      expect(widget).not_to be_valid
      expect(widget.errors[:pre_chat_form_options].join).to include('mode')
    end

    it 'aceita formulario SEM modo — a frota inteira esta assim, e o front deriva' do
      widget = described_class.new(
        account: account,
        website_url: 'https://exemplo.com.br',
        pre_chat_form_options: { 'pre_chat_fields' => [base_field] }
      )

      expect(widget).to be_valid
    end

    it 'NAO aceita flow_id: o alvo do fluxo se resolve pelo gatilho no servidor, nao aqui' do
      widget = described_class.new(
        account: account,
        website_url: 'https://exemplo.com.br',
        pre_chat_form_options: { 'mode' => 'flow', 'flow_id' => 7, 'pre_chat_fields' => [base_field] }
      )

      expect(widget).not_to be_valid
      expect(widget.errors[:pre_chat_form_options].join).to include('flow_id')
    end
  end

  describe 'compatibilidade com o que ja esta gravado na frota' do
    # A tela antiga (`PreChatForm/Settings.vue:78`) grava TODOS os atributos
    # personalizados da conta no array, com `enabled: false`. Uma conta com 12
    # atributos tem 12 entradas ha muito tempo — por isso o schema NAO tem
    # `maxItems`. O teto de 8 e sobre campo HABILITADO e e regra da tela.
    it 'aceita array com 12 campos, porque o teto de 8 conta campo habilitado, nao entrada do array' do
      fields = Array.new(12) { |i| base_field('name' => "attr_#{i}", 'enabled' => false) }

      expect(build_widget(fields)).to be_valid
    end

    it 'aceita campo legado com chave que o schema nao declara' do
      widget = build_widget([base_field('locale' => 'pt_BR', 'values' => %w[a b], 'regex_pattern' => '/x/', 'regex_cue' => 'oi')])

      expect(widget).to be_valid
    end

    it 'aceita a semente de fabrica, que nao tem nenhuma das sete chaves novas' do
      widget = described_class.new(account: account, website_url: 'https://exemplo.com.br')

      expect(widget).to be_valid
    end
  end
end
