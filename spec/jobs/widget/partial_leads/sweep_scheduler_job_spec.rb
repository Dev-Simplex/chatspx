# frozen_string_literal: true

require 'rails_helper'

# 4.18 — O JOB SO EXISTE SE ELE RODA.
#
# O `SweepJob` estava escrito e testado (materializa o abandono, expurga o vencido) e nao
# tinha entrada em `config/schedule.yml`. Sem essa entrada nada nele acontece: o lead
# incompleto nunca vira contato no painel e o registro parcial nunca e apagado — que e o
# aceite inteiro do bloco, e a mesma classe de defeito que o `Flows::ResumeJob` (4.14) pagou:
# codigo pronto, comentario afirmando "roda a cada minuto" e nenhuma linha no agendador.
#
# Este arquivo prova as duas metades: o agendador EXISTE (e aponta para uma classe que
# resolve, na frequencia que a configuracao promete) e o leque FAZ o que a configuracao diz.
RSpec.describe Widget::PartialLeads::SweepSchedulerJob do
  let(:schedule) { YAML.load_file(Rails.root.join('config/schedule.yml')) }
  let(:entrada) { schedule['widget_partial_leads_sweep_job'] }

  describe 'a entrada do cron' do
    it 'existe e aponta para ESTA classe' do
      expect(entrada).to be_present
      expect(entrada['class']).to eq(described_class.name)
    end

    it 'roda numa fila que drena — nao na `:low`, que aqui ja foi medida como faminta' do
      # `config/sidekiq.yml` usa prioridade estrita e a `:low` fica abaixo da `:default`. O
      # efeito esta escrito na entrada do `waha_refresh_groups_job`: "em producao carregada a
      # :low quase nunca drenava". Um varredor agendado numa fila que nao drena e um varredor
      # que nao roda com o sistema ocupado — o mesmo defeito com outro nome.
      expect(entrada['queue']).to eq('scheduled_jobs')
      expect(described_class.new.queue_name).to eq('scheduled_jobs')
      expect(Widget::PartialLeads::SweepJob.new.queue_name).to eq('scheduled_jobs')
    end

    it 'roda com folga para a MENOR janela de abandono que a tela pode configurar' do
      # A tela oferece 2 minutos (mockup 22 §3) e o clamp aceita ate 1 minuto. Um cron de 5 em
      # 5 faria a configuracao prometer 2 e entregar ate 7 — configuracao que mente sobre o
      # proprio efeito e o defeito que este bloco existe para nao repetir.
      minutos = entrada['cron'].split.first
      passo = minutos.start_with?('*/') ? minutos.delete_prefix('*/').to_i : 60

      expect(passo).to be <= Widget::PartialLeads::Settings::MIN_ABANDON_MINUTES
    end
  end

  describe 'o leque' do
    let(:account) { create(:account) }
    let(:inbox) { create(:channel_widget, account: account).inbox }

    it 'enfileira UM SweepJob por conta que tem resposta parcial parada' do
      create(:widget_partial_lead, account: account, inbox: inbox, last_answered_at: 10.minutes.ago)
      create(:widget_partial_lead, account: account, inbox: inbox, last_answered_at: 20.minutes.ago)

      expect { described_class.perform_now }
        .to have_enqueued_job(Widget::PartialLeads::SweepJob).with(account.id).exactly(:once)
    end

    it 'nao acorda conta nenhuma quando nao ha resposta parcial — o cron roda a cada minuto' do
      account && inbox

      expect { described_class.perform_now }.not_to have_enqueued_job(Widget::PartialLeads::SweepJob)
    end

    it 'ignora o rascunho respondido AGORA: ele nao esta abandonado sob nenhuma configuracao' do
      create(:widget_partial_lead, account: account, inbox: inbox, last_answered_at: Time.current)

      expect { described_class.perform_now }.not_to have_enqueued_job(Widget::PartialLeads::SweepJob)
    end

    it 'inclui a conta que DESLIGOU a captura — o expurgo de retencao (LGPD) e dela tambem' do
      account.update!(internal_attributes: account.internal_attributes.merge('partial_lead_capture_enabled' => false))
      create(:widget_partial_lead, account: account, inbox: inbox, last_answered_at: 40.days.ago)

      expect { described_class.perform_now }
        .to have_enqueued_job(Widget::PartialLeads::SweepJob).with(account.id)
    end

    it 'separa as contas: cada uma recebe o seu proprio job' do
      outra = create(:account)
      outra_inbox = create(:channel_widget, account: outra).inbox
      create(:widget_partial_lead, account: account, inbox: inbox, last_answered_at: 10.minutes.ago)
      create(:widget_partial_lead, account: outra, inbox: outra_inbox, last_answered_at: 10.minutes.ago)

      expect { described_class.perform_now }
        .to have_enqueued_job(Widget::PartialLeads::SweepJob).exactly(:twice)
    end
  end

  # O aceite do bloco, percorrido pelo caminho que o cron percorre: nada de chamar o
  # `SweepJob` a mao. Se o leque parar de enfileirar, ESTE exemplo cai — e ele e o unico que
  # liga "o visitante sumiu" a "o lead esta no painel".
  describe 'o caminho completo, do cron ao painel' do
    let(:account) { create(:account) }
    let(:web_widget) { create(:channel_widget, account: account) }
    let(:inbox) { web_widget.inbox }

    it 'o visitante que sumiu vira contato marcado como incompleto, com a etapa em que parou' do
      account.update!(internal_attributes: account.internal_attributes.merge('partial_lead_capture_enabled' => true))
      contact = create(:contact, account: account, email: nil, phone_number: nil)
      contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox)
      create(:widget_partial_lead, account: account, inbox: inbox, session_id: contact_inbox.source_id,
                                   answers: { 'fullName' => 'Walisson', 'emailAddress' => 'walisson@empresa.com.br' },
                                   step_reached: 3, step_key: 'phoneNumber', last_answered_at: 30.minutes.ago)

      # `only:` de proposito: sem ele o `perform_enqueued_jobs` tambem roda o job de avatar
      # que o `ContactIdentifyAction` enfileira, e o spec passaria a medir o Gravatar.
      perform_enqueued_jobs(only: Widget::PartialLeads::SweepJob) { described_class.perform_now }

      expect(contact.reload.email).to eq('walisson@empresa.com.br')
      expect(contact.custom_attributes['widget_lead_incomplete']).to be(true)
      expect(contact.custom_attributes['widget_lead_step']).to eq(3)
      expect(contact.custom_attributes['widget_lead_step_name']).to eq('phoneNumber')
      expect(contact.label_list).to include('lead-incompleto')
    end
  end
end
