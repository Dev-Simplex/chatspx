# frozen_string_literal: true

require 'rails_helper'

# 4.21 — A INSTRUMENTACAO DOS TRES NIVEIS, percorrida como o dado nasce.
#
# O aceite do bloco: "uma consulta responde 'qual nivel converte mais nesta conta' sem abrir
# console de ninguem; o evento traz `approach` E `approach_configured`; exibicao sem abertura
# tambem e registrada — sem denominador nao ha medicao; nenhum dado pessoal no payload".
#
# E a armadilha herdada do 5.03 (§4.2 do contrato): o mesmo fato registrado duas vezes e um
# registro so. Aqui a retentativa vem da rede e do proprio visitante, e a trava consumida e a
# mesma — indice unico `(account_id, name, dedup_key)`.
RSpec.describe '/api/v1/widget/approach_events (4.21)', type: :request do
  let(:account) { create(:account) }
  let(:web_widget) { create(:channel_widget, account: account) }
  let(:contact) { create(:contact, account: account, email: nil, phone_number: nil) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: web_widget.inbox) }
  let(:token) do
    Widget::TokenService.new(payload: { source_id: contact_inbox.source_id, inbox_id: web_widget.inbox.id }).generate_token
  end

  after { Current.reset }

  def registra(stage: 'shown', approach: 'bold', configurado: 'bold', ordinal: 1, headers: nil)
    post '/api/v1/widget/approach_events',
         params: { website_token: web_widget.website_token, stage: stage, approach: approach,
                   approach_configured: configurado, ordinal: ordinal },
         headers: headers || { 'X-Auth-Token' => token },
         as: :json
  end

  describe 'o fato registrado' do
    it 'grava a exibicao com o nivel efetivo e o configurado SEPARADOS' do
      expect { registra(approach: 'discreet', configurado: 'bold', ordinal: 2) }
        .to change(TrackingEvent, :count).by(1)

      evento = TrackingEvent.last
      expect(evento.name).to eq('chatspx_approach_shown')
      expect(evento.properties).to eq(
        'approach' => 'discreet', 'approach_configured' => 'bold', 'degraded' => true
      )
      expect(evento.source).to eq('widget')
    end

    it 'o fato nasce com dono: conta, inbox, contato e o event_id do servidor' do
      registra

      evento = TrackingEvent.last
      expect(evento.account_id).to eq(account.id)
      expect(evento.inbox_id).to eq(web_widget.inbox.id)
      expect(evento.contact_id).to eq(contact.id)
      expect(evento.event_id).to be_present
    end

    it 'nivel que nao caiu vem com degraded: false — e o que separa o efeito do nivel do da degradacao' do
      registra(approach: 'bold', configurado: 'bold')

      expect(TrackingEvent.last.properties['degraded']).to be(false)
    end

    it 'as quatro etapas viram quatro nomes, e o SERVIDOR e quem os compoe' do
      %w[shown dismissed opened converted].each_with_index do |stage, i|
        registra(stage: stage, ordinal: i + 1)
      end

      expect(TrackingEvent.pluck(:name)).to contain_exactly(
        'chatspx_approach_shown', 'chatspx_approach_dismissed',
        'chatspx_approach_opened', 'chatspx_approach_converted'
      )
    end

    it 'EXIBICAO SEM ABERTURA tambem e registrada — sem denominador nao ha medicao' do
      registra(stage: 'shown')

      expect(TrackingEvent.where(name: 'chatspx_approach_shown').count).to eq(1)
      expect(TrackingEvent.where(name: 'chatspx_approach_opened')).to be_empty
    end

    it 'nao carrega dado pessoal: as chaves do payload sao as tres da configuracao' do
      registra

      expect(TrackingEvent.last.properties.keys).to contain_exactly('approach', 'approach_configured', 'degraded')
    end
  end

  # ── A ARMADILHA HERDADA ─────────────────────────────────────────────────────────────────
  describe 'idempotencia — a trava do 5.03 consumida, nao contornada' do
    it 'o MESMO fato reenviado e um registro so' do
      registra(stage: 'shown', ordinal: 1)

      expect { registra(stage: 'shown', ordinal: 1) }.not_to change(TrackingEvent, :count)
      expect(response).to have_http_status(:no_content)
    end

    it 'tres mensagens seguidas do visitante sao UMA conversao' do
      registra(stage: 'converted', ordinal: 1)
      registra(stage: 'converted', ordinal: 1)
      registra(stage: 'converted', ordinal: 1)

      expect(TrackingEvent.where(name: 'chatspx_approach_converted').count).to eq(1)
    end

    it 'a chave deriva do FATO, nao do relogio: o mesmo ordinal colide mesmo em segundos diferentes' do
      travel_to(Time.zone.parse('2026-08-19 10:00:00')) { registra(stage: 'shown', ordinal: 1) }
      travel_to(Time.zone.parse('2026-08-19 10:00:37')) { registra(stage: 'shown', ordinal: 1) }

      expect(TrackingEvent.count).to eq(1)
    end

    it 'ordinais diferentes sao fatos diferentes — a abordagem seguinte NAO e engolida' do
      registra(stage: 'shown', ordinal: 1)
      registra(stage: 'shown', ordinal: 2)

      expect(TrackingEvent.count).to eq(2)
    end

    # Este vale COM e SEM a `dedup_key` explicita — a derivacao padrao ja separa por
    # `contact_id`. Fica como propriedade do endpoint, nao como prova da chave: sabotar a
    # chave nao o derruba, e chamar de prova seria vender um verde que nao mede o que diz.
    it 'DOIS VISITANTES no mesmo segundo nao viram um evento so' do
      outro_contato = create(:contact, account: account)
      outro_inbox = create(:contact_inbox, contact: outro_contato, inbox: web_widget.inbox)
      outro_token = Widget::TokenService.new(
        payload: { source_id: outro_inbox.source_id, inbox_id: web_widget.inbox.id }
      ).generate_token

      travel_to(Time.zone.parse('2026-08-19 10:00:00')) do
        registra(stage: 'shown', ordinal: 1)
        registra(stage: 'shown', ordinal: 1, headers: { 'X-Auth-Token' => outro_token })
      end

      expect(TrackingEvent.count).to eq(2)
    end
  end

  describe 'a porta fechada' do
    it 'recusa etapa fora do contrato — nome de evento nao vem do site do cliente' do
      expect { registra(stage: 'chatspx_qualquer_coisa') }.not_to change(TrackingEvent, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'recusa nivel fora do vocabulario do schema 3.20' do
      expect { registra(approach: 'insano') }.not_to change(TrackingEvent, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'recusa ordinal absurdo — inteiro pequeno do navegador nao vira dado com cara de dado' do
      expect { registra(ordinal: 2_147_483_647) }.not_to change(TrackingEvent, :count)
      expect { registra(ordinal: 0) }.not_to change(TrackingEvent, :count)
    end

    it 'sem token de sessao nao grava nada — a sessao e metade da chave de dedup' do
      expect { registra(headers: {}) }.not_to change(TrackingEvent, :count)
    end
  end

  # O aceite em uma frase: "uma consulta responde qual nivel converte mais nesta conta".
  describe 'a consulta que o bloco existe para tornar possivel' do
    it 'responde exibicoes e conversoes por nivel, sem abrir console de ninguem' do
      registra(stage: 'shown', approach: 'bold', ordinal: 1)
      registra(stage: 'converted', approach: 'bold', ordinal: 1)
      registra(stage: 'shown', approach: 'discreet', configurado: 'bold', ordinal: 2)

      por_nivel = TrackingEvent.where(account_id: account.id)
                               .group("properties->>'approach'", :name).count

      expect(por_nivel[%w[bold chatspx_approach_shown]]).to eq(1)
      expect(por_nivel[%w[bold chatspx_approach_converted]]).to eq(1)
      expect(por_nivel[%w[discreet chatspx_approach_shown]]).to eq(1)
      expect(por_nivel[%w[discreet chatspx_approach_converted]]).to be_nil
    end
  end
end
