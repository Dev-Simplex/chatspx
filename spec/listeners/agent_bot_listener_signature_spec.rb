require 'rails_helper'

# Bloco 4.13 — a assinatura do caminho de agent bot, medida ATE O CABECALHO.
#
# O spec vizinho (`agent_bot_listener_spec.rb`) prova que o listener passa `secret:` para o
# job. Isso ainda nao prova assinatura: passar um segredo e uma coisa, o POST sair com um
# `X-Chatwoot-Signature` que o destino consegue conferir e outra. Aqui a corrente e
# percorrida inteira — listener → job → `Webhooks::Trigger` → cabecalhos do POST — e o HMAC
# e recalculado do lado de fora, como faria quem recebe.
RSpec.describe AgentBotListener do
  include ActiveJob::TestHelper

  let(:listener) { described_class.instance }
  let!(:account) { create(:account) }
  let!(:inbox) { create(:inbox, account: account) }
  let!(:agent_bot) { create(:agent_bot, account: account, outgoing_url: 'https://bot.exemplo.com/hook') }
  let!(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let!(:message) { create(:message, message_type: 'outgoing', account: account, inbox: inbox, conversation: conversation) }
  let(:event) { Events::Base.new('message.created', Time.zone.now, message: message) }

  # Captura o que o `Webhooks::Trigger` REALMENTE mandaria pela rede, e junto o que o
  # listener enfileirou — os dois lados da corrente, para poder confrontar um com o outro.
  def requisicao_do_bot
    capturada = nil
    enfileirado = nil
    allow(SafeFetch).to receive(:fetch) do |url, **opcoes|
      capturada = { url: url, body: opcoes[:body], headers: opcoes[:headers] }
      nil
    end
    allow(AgentBots::WebhookJob).to receive(:perform_later).and_wrap_original do |original, *args, **kwargs|
      enfileirado = kwargs
      original.call(*args, **kwargs)
    end
    perform_enqueued_jobs { listener.message_created(event) }
    capturada.merge(enfileirado: enfileirado || {})
  end

  before do
    ActiveJob::Base.queue_adapter = :test
    # Sem nome: este registro existe para LIGAR o bot a inbox — e o que faz o listener
    # escolhe-lo —, nao para ser lido por nenhum exemplo.
    create(:agent_bot_inbox, inbox: inbox, agent_bot: agent_bot)
  end

  after do
    clear_enqueued_jobs
    clear_performed_jobs
  end

  it 'assina o POST com o segredo do bot, e a assinatura confere do lado de fora' do
    requisicao = requisicao_do_bot

    expect(requisicao[:url]).to eq(agent_bot.outgoing_url)
    expect(agent_bot.secret).to be_present

    timestamp = requisicao[:headers]['X-Chatwoot-Timestamp']
    esperada = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', agent_bot.secret, "#{timestamp}.#{requisicao[:body]}")}"

    expect(timestamp).to be_present
    expect(requisicao[:headers]['X-Chatwoot-Signature']).to eq(esperada)
  end

  # A verificacao tem de ser sensivel ao segredo, senao ela nao verifica nada: uma
  # assinatura que confere com QUALQUER chave e um cabecalho decorativo. A primeira
  # expectativa e o que impede este exemplo de passar por AUSENCIA — sem ela, um POST sem
  # assinatura nenhuma tambem "nao confere com a chave errada".
  it 'a assinatura NAO confere com outro segredo' do
    requisicao = requisicao_do_bot

    timestamp = requisicao[:headers]['X-Chatwoot-Timestamp']
    com_chave_errada = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', 'chave-errada', "#{timestamp}.#{requisicao[:body]}")}"

    expect(requisicao[:headers]['X-Chatwoot-Signature']).to be_present
    expect(requisicao[:headers]['X-Chatwoot-Signature']).not_to eq(com_chave_errada)
  end

  # T-I5.2. O cabecalho ja aparecia antes desta mudanca, so que preenchido com o `job_id`
  # (o fallback do WebhookJob) — um id que nasce do JOB, nao do evento. Agora quem o gera e
  # o listener, no momento do evento, e e esse valor que chega ao destino: a diferenca
  # entre "cada despacho tem um id" e "este EVENTO tem um id".
  it 'o delivery id do POST e o que o listener gerou para o evento' do
    requisicao = requisicao_do_bot

    expect(requisicao[:enfileirado][:delivery_id]).to be_present
    expect(requisicao[:headers]['X-Chatwoot-Delivery']).to eq(requisicao[:enfileirado][:delivery_id])
  end

  # Sem segredo nao ha o que assinar — e um cabecalho de assinatura vazio ou calculado
  # sobre string vazia seria pior do que nenhum: daria ao destino a impressao de que
  # existe verificacao.
  it 'bot sem segredo sai sem cabecalho de assinatura' do
    AgentBot.where(id: agent_bot.id).update_all(secret: nil) # rubocop:disable Rails/SkipsModelValidations
    # `reload` obrigatorio: a mensagem carrega a inbox em cache, e a inbox carrega o bot.
    # Sem isso o listener continua lendo o objeto anterior — com o segredo antigo — e o
    # teste passaria medindo o registro que ele mesmo criou, nao o que esta no banco.
    message.reload

    requisicao = requisicao_do_bot

    expect(requisicao[:headers]).not_to have_key('X-Chatwoot-Signature')
    expect(requisicao[:headers]).not_to have_key('X-Chatwoot-Timestamp')
  end
end
