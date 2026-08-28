# frozen_string_literal: true

require 'rails_helper'

# 3.18 — A PRECEDENCIA, DO LADO QUE GRAVA.
#
# A clausula do aceite: "com `chatwootSettings.position` presente no site, o widget usa o do site
# E A TELA AVISA". A primeira metade e do SDK; esta e a segunda. A tela de aparencia roda no painel
# e nao tem como ler o HTML do site do cliente — ela so sabe o que o widget, que roda la, contar.
#
# O ESTADO ANTERIOR, MEDIDO: `AppearancePage.vue:67` ja lia
# `additional_attributes['widget_appearance_overrides']`, e essa chave nao tinha produtor nenhum em
# lugar algum do produto. `overriddenFields` era `[]` para sempre, o aviso amarelo era inerte, e o
# unico teste que o aprovava nascia de uma fixture que inventava a chave.
RSpec.describe '/api/v1/widget/appearance_overrides (3.18)', type: :request do
  let(:account) { create(:account) }
  let(:web_widget) { create(:channel_widget, account: account) }
  let(:inbox) { web_widget.inbox }
  let(:contact) { create(:contact, account: account, email: nil, phone_number: nil) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:token) do
    Widget::TokenService.new(payload: { source_id: contact_inbox.source_id, inbox_id: inbox.id }).generate_token
  end

  after { Current.reset }

  def reporta(fields, headers: nil)
    post '/api/v1/widget/appearance_overrides',
         params: { website_token: web_widget.website_token, fields: fields },
         headers: headers || { 'X-Auth-Token' => token },
         as: :json
  end

  def gravado
    inbox.reload.additional_attributes['widget_appearance_overrides']
  end

  describe 'o que a tela passa a poder ler' do
    it 'grava os campos sobrescritos pelo site' do
      reporta(%w[position theme])

      expect(response).to have_http_status(:no_content)
      expect(gravado).to eq(%w[theme position])
    end

    it 'a lista VAZIA tambem e um fato — e o que apaga um aviso que ficou velho' do
      inbox.update!(additional_attributes: inbox.additional_attributes.merge('widget_appearance_overrides' => %w[position]))

      reporta([])

      expect(gravado).to eq([])
    end

    it 'a ordem gravada e a do schema, nao a de chegada' do
      # O valor gravado e comparado com o anterior para decidir se ha escrita. Duas listas com os
      # mesmos campos em ordens diferentes nunca seriam iguais, e o atalho de "nada mudou" — que e
      # o que poupa a validacao a cada boot do widget — nunca pegaria.
      reporta(%w[panel_style position theme])

      expect(gravado).to eq(%w[theme position panel_style])
    end

    it 'campo repetido nao duplica' do
      reporta(%w[position position])

      expect(gravado).to eq(%w[position])
    end

    it 'nao encosta nas outras chaves de `additional_attributes`' do
      inbox.update!(additional_attributes: inbox.additional_attributes.merge('widget_appearance' => { 'position' => 'left' }))

      reporta(%w[position])

      expect(inbox.reload.additional_attributes['widget_appearance']).to eq({ 'position' => 'left' })
    end
  end

  describe 'a lista e fechada' do
    it 'recusa nome que nao esta em OVERRIDABLE_BY_SITE' do
      reporta(%w[position offset_x])

      expect(response).to have_http_status(:unprocessable_entity)
      expect(gravado).to be_nil
    end

    it 'recusa texto livre — `additional_attributes` vai para o HTML de toda pagina do cliente' do
      reporta(['<script>alert(1)</script>'])

      expect(response).to have_http_status(:unprocessable_entity)
      expect(gravado).to be_nil
    end

    it 'AUSENCIA nao e lista vazia: sem `fields` recusa, para um chamador antigo nao zerar a lista' do
      inbox.update!(additional_attributes: inbox.additional_attributes.merge('widget_appearance_overrides' => %w[position]))

      post '/api/v1/widget/appearance_overrides',
           params: { website_token: web_widget.website_token },
           headers: { 'X-Auth-Token' => token },
           as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(gravado).to eq(%w[position])
    end

    it 'a lista aceita e exatamente a do schema — sem terceiro vocabulario' do
      WidgetAppearanceSchema::OVERRIDABLE_BY_SITE.each_key do |campo|
        reporta([campo])
        expect(response).to have_http_status(:no_content), "campo #{campo} recusado"
      end
    end
  end

  describe 'inbox com jsonb legado invalido' do
    it 'nao vira 500 por pageview: recusa com 422 e segue' do
      # A condicao ruim FORCADA, e ela e real: `update_column` grava sem passar pela validacao,
      # que e por onde uma inbox anterior ao schema (ou um caminho que o burlou) chegou ao estado
      # de hoje. Dai em diante QUALQUER `update!` naquela linha e recusado — inclusive este, que
      # nem toca em `widget_appearance`. Como este endpoint e chamado a cada boot do widget, um
      # unico registro legado viraria um erro por visita no nosso log.
      #
      # Quem impede o 500 sao DUAS camadas que ja existem, e isto foi MEDIDO, nao suposto: o
      # `rescue_from ActiveRecord::RecordInvalid` de `RequestExceptionHandler` e, atras dele, o
      # proprio Rails, que mapeia `RecordInvalid` para 422 em `rescue_responses` — sabotar so o
      # primeiro NAO deixa este exemplo vermelho, e foi assim que se descobriu que um `rescue`
      # neste controller seria codigo morto. O que este exemplo trava, entao, e o que o controller
      # PODE estragar: levantar um erro proprio (que viraria 500) ou gravar mesmo assim.
      # rubocop:disable Rails/SkipsModelValidations -- pular a validacao E o ponto: e por aqui que uma
      # inbox anterior ao schema chegou ao estado que se quer reproduzir. Escrever pelo caminho
      # validado seria impossivel, e o exemplo mediria um estado que producao nao tem.
      inbox.update_column(:additional_attributes, inbox.additional_attributes.merge('widget_appearance' => { 'position' => 'centro' }))
      # rubocop:enable Rails/SkipsModelValidations

      reporta(%w[position])

      expect(response).to have_http_status(:unprocessable_entity)
      expect(gravado).to be_nil
    end
  end

  describe 'quem pode escrever' do
    it 'sem token nao grava' do
      reporta(%w[position], headers: {})

      expect(response).not_to have_http_status(:no_content)
      expect(gravado).to be_nil
    end

    it 'a inbox vem do TOKEN, nunca do corpo' do
      outra = create(:channel_widget, account: account).inbox

      post '/api/v1/widget/appearance_overrides',
           params: { website_token: web_widget.website_token, inbox_id: outra.id, fields: %w[position] },
           headers: { 'X-Auth-Token' => token },
           as: :json

      expect(gravado).to eq(%w[position])
      expect(outra.reload.additional_attributes['widget_appearance_overrides']).to be_nil
    end
  end

  describe 'o relatorio sai a cada pageview — a escrita nao pode' do
    it 'reenvio identico nao escreve de novo' do
      reporta(%w[position])
      antes = inbox.reload.updated_at

      travel_to(1.hour.from_now) { reporta(%w[position]) }

      expect(response).to have_http_status(:no_content)
      expect(inbox.reload.updated_at).to eq(antes)
    end

    it 'reenvio identico nem chega a validar — e ISSO que o atalho compra' do
      # MEDIDO: tirar o `return head :no_content if ... == reported_fields` NAO faz o exemplo
      # acima cair, porque o proprio ActiveRecord nao emite UPDATE quando nada mudou. O que o
      # atalho compra e outra coisa, e so este exemplo a mostra: sem ele, o `update!` ainda RODA
      # AS VALIDACOES, e uma inbox com jsonb legado invalido passaria a devolver 422 a cada boot
      # do widget — para reenviar uma lista que ja estava gravada e correta.
      reporta(%w[position])
      # rubocop:disable Rails/SkipsModelValidations -- ver o exemplo da inbox legada: forcar o estado
      # invalido e a unica forma de medir o que o atalho de "nada mudou" compra.
      inbox.update_column(
        :additional_attributes,
        inbox.reload.additional_attributes.merge('widget_appearance' => { 'position' => 'centro' })
      )
      # rubocop:enable Rails/SkipsModelValidations

      reporta(%w[position])

      expect(response).to have_http_status(:no_content)
    end

    it 'mudanca real escreve' do
      reporta(%w[position])

      travel_to(1.hour.from_now) { reporta(%w[position theme]) }

      expect(gravado).to eq(%w[theme position])
    end
  end

  # A metade do aceite que so faz sentido junto: as DUAS fontes preenchidas e divergentes.
  describe 'as duas fontes preenchidas e divergentes' do
    it 'o banco continua dizendo `left`, o site sobrescreveu `position`, e a tela le as duas coisas' do
      inbox.update!(additional_attributes: inbox.additional_attributes.merge('widget_appearance' => { 'position' => 'left' }))

      reporta(%w[position])

      atributos = inbox.reload.additional_attributes
      # O que o admin configurou (e o que a tela mostra no campo)...
      expect(inbox.resolved_widget_appearance['position']).to eq('left')
      # ...e o fato de o site estar vencendo nesse campo (e o que dispara o aviso).
      expect(atributos['widget_appearance_overrides']).to eq(%w[position])
    end
  end
end
