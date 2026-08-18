require 'rails_helper'

# Bloco 5.04 / T-C3.7 — `chatspx_lead` (evento #5 do contrato).
#
# O fato e "o contato PASSOU A TER e-mail ou telefone". A palavra que importa e PASSOU: e uma
# transicao, e so o servidor a enxerga. O widget ve estado ("este contato tem e-mail") e nao
# distingue quem acabou de digitar de quem ja era identificado e recarregou a pagina.
describe TrackingEventListener do
  let(:listener) { described_class.instance }
  let!(:account) { create(:account) }
  let!(:inbox) { create(:inbox, account: account) }
  let!(:contact) { create(:contact, account: account, email: nil, phone_number: nil) }

  def updated_event(contact_record, changes, at: Time.zone.now)
    Events::Base.new('contact.updated', at, contact: contact_record, changed_attributes: changes)
  end

  def created_event(contact_record, at: Time.zone.now)
    Events::Base.new('contact.created', at, contact: contact_record)
  end

  def lead_events
    TrackingEvent.where(name: 'chatspx_lead')
  end

  describe '#contact_updated' do
    it 'grava chatspx_lead quando o e-mail aparece pela primeira vez' do
      listener.contact_updated(updated_event(contact, { 'email' => [nil, 'ana@exemplo.com.br'] }))

      event = lead_events.last
      expect(event).to be_present
      expect(event.event_id).to match(/\A[0-9a-f-]{36}\z/)
      expect(event.account_id).to eq(account.id)
      expect(event.contact_id).to eq(contact.id)
      expect(event.source).to eq('server')
    end

    it 'grava tambem quando o identificador novo e o telefone' do
      listener.contact_updated(updated_event(contact, { 'phone_number' => ['', '+5565999990000'] }))

      expect(lead_events.count).to eq(1)
    end

    it 'NAO grava quando o contato apenas troca de e-mail — ele ja era lead' do
      listener.contact_updated(
        updated_event(contact, { 'email' => ['antigo@exemplo.com.br', 'novo@exemplo.com.br'] })
      )

      expect(lead_events.count).to eq(0)
    end

    it 'NAO grava quando a mudanca nao envolve identificador nenhum' do
      listener.contact_updated(updated_event(contact, { 'name' => ['Ana', 'Ana Prado'] }))

      expect(lead_events.count).to eq(0)
    end

    it 'NAO grava quando o evento chega sem changed_attributes' do
      listener.contact_updated(Events::Base.new('contact.updated', Time.zone.now, contact: contact))

      expect(lead_events.count).to eq(0)
    end

    it 'aceita changed_attributes com chave simbolo, que e como o dispatcher normaliza as vezes' do
      listener.contact_updated(updated_event(contact, { email: [nil, 'ana@exemplo.com.br'] }))

      expect(lead_events.count).to eq(1)
    end

    # A ARMADILHA DO BLOCO, e ela e a razao da dedup_key explicita.
    it 'grava UM evento quando o contato ganha e-mail e, segundos depois, telefone' do
      listener.contact_updated(
        updated_event(contact, { 'email' => [nil, 'ana@exemplo.com.br'] },
                      at: Time.zone.parse('2026-08-18 09:00:01'))
      )
      listener.contact_updated(
        updated_event(contact, { 'phone_number' => [nil, '+5565999990000'] },
                      at: Time.zone.parse('2026-08-18 09:00:09'))
      )

      # Sem `dedup_key` presa ao contato, a derivacao padrao usaria `occurred_at.to_i` e os dois
      # instantes produziriam DOIS event_id — duas conversoes contadas na Meta pelo mesmo lead.
      expect(lead_events.count).to eq(1)
    end

    it 'grava UM evento quando o job e retentado com o mesmo fato' do
      moment = Time.zone.parse('2026-08-18 09:30:00')
      2.times do
        listener.contact_updated(updated_event(contact, { 'email' => [nil, 'ana@exemplo.com.br'] }, at: moment))
      end

      expect(lead_events.count).to eq(1)
    end

    it 'guarda o instante do FATO, nao o da gravacao' do
      moment = Time.zone.parse('2026-08-18 09:30:00')

      listener.contact_updated(updated_event(contact, { 'email' => [nil, 'a@b.com'] }, at: moment))

      expect(lead_events.last.occurred_at).to be_within(1.second).of(moment)
    end

    it 'amarra o evento a conversa mais recente do contato, com a inbox dela' do
      create(:conversation, account: account, inbox: inbox, contact: contact,
                            created_at: 2.days.ago)
      recente = create(:conversation, account: account, inbox: inbox, contact: contact,
                                      created_at: 1.hour.ago)

      listener.contact_updated(updated_event(contact, { 'email' => [nil, 'a@b.com'] }))

      event = lead_events.last
      expect(event.conversation_id).to eq(recente.id)
      expect(event.inbox_id).to eq(inbox.id)
    end

    it 'grava lead_source com o canal da conversa' do
      create(:conversation, account: account, inbox: inbox, contact: contact)

      listener.contact_updated(updated_event(contact, { 'email' => [nil, 'a@b.com'] }))

      expect(lead_events.last.properties).to eq({ 'lead_source' => 'Channel::WebWidget' })
    end

    it 'grava lead_source "contact" quando o contato ainda nao tem conversa' do
      listener.contact_updated(updated_event(contact, { 'email' => [nil, 'a@b.com'] }))

      expect(lead_events.last.properties).to eq({ 'lead_source' => 'contact' })
    end

    it 'NAO deixa PII crua entrar em properties' do
      listener.contact_updated(updated_event(contact, { 'email' => [nil, 'ana@exemplo.com.br'] }))

      expect(lead_events.last.properties.to_json).not_to include('ana@exemplo.com.br')
    end

    it 'nao quebra a atualizacao do contato quando o registro falha' do
      allow(Tracking::EventRecorder).to receive(:record!).and_raise(StandardError.new('banco fora'))
      exception_tracker = instance_double(ChatwootExceptionTracker, capture_exception: true)
      allow(ChatwootExceptionTracker).to receive(:new).and_return(exception_tracker)

      expect { listener.contact_updated(updated_event(contact, { 'email' => [nil, 'a@b.com'] })) }
        .not_to raise_error
      expect(ChatwootExceptionTracker).to have_received(:new)
    end
  end

  describe '#contact_created' do
    it 'grava quando o contato ja nasce com identificador' do
      identificado = create(:contact, account: account, email: 'nasceu@exemplo.com.br')

      listener.contact_created(created_event(identificado))

      expect(lead_events.count).to eq(1)
      expect(lead_events.last.contact_id).to eq(identificado.id)
    end

    it 'NAO grava para o visitante anonimo, que e a maioria' do
      listener.contact_created(created_event(contact))

      expect(lead_events.count).to eq(0)
    end

    it 'nao duplica quando o contato nasce identificado e depois e atualizado' do
      identificado = create(:contact, account: account, email: 'nasceu@exemplo.com.br')

      listener.contact_created(created_event(identificado))
      listener.contact_updated(
        updated_event(identificado, { 'phone_number' => [nil, '+5565999990000'] })
      )

      expect(lead_events.count).to eq(1)
    end
  end

  describe 'nao existe segundo emissor do mesmo fato' do
    it 'o evento de tracking do lead nasce SO no servidor' do
      # RG4: uma emissao por fato. O widget emite `chatwoot:lead-identified`, que e o outro
      # VOCABULARIO (arbitragem A9) e nao chega a esta tabela. Se algum dia um caminho do widget
      # passar a gravar `chatspx_lead`, este teste continua valendo como documentacao do contrato:
      # a fonte do evento de tracking e `server`.
      listener.contact_updated(updated_event(contact, { 'email' => [nil, 'a@b.com'] }))

      expect(lead_events.pluck(:source).uniq).to eq(['server'])
    end
  end
end
