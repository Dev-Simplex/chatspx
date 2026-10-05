# Leva o cliente para outro canal da empresa: o sistema manda a abertura pela caixa de destino e o
# atendimento continua lá (Whatsapp::ContactInviteService com `destino:`). A IA escolhe o canal pelo
# nome da lista que recebe no contexto; o número do canal nunca passa por ela.
#
# Os destinos são as caixas da unidade da conversa marcadas como destino ou como WhatsApp
# principal (InboxCanal, configurado na tela de unidades). Sem nenhuma na conta, a ferramenta nem
# entra no toolset.
class Captain::Tools::LevarAoCanalTool < Captain::Tools::BasePublicTool
  description 'Leva o cliente para outro canal da empresa: o sistema envia a ele, pelo canal escolhido, uma mensagem de ' \
              'abertura, e o atendimento continua lá. Use quando o que o cliente precisa é papel de outro canal da ' \
              'lista de canais do seu contexto, ou quando ele pede para ser chamado no WhatsApp. Antes de chamar, avise ' \
              'o cliente com suas palavras que vai chamá-lo por lá. Você nunca vê nem informa número de telefone de canal.'

  param :canal, type: 'string',
                desc: 'O nome do canal de destino, escrito como aparece na lista de canais do seu contexto.',
                required: true
  param :motivo, type: 'string',
                 desc: 'A frase que o cliente vai LER na abertura, dizendo por que está sendo chamado ali: o assunto que ' \
                       'ele trouxe. Em segunda pessoa, curta e clara.',
                 required: true
  param :telefone, type: 'string',
                   desc: 'O número de WhatsApp que o cliente informou nesta conversa, com DDD. Deixe vazio quando esta ' \
                         'conversa já é no WhatsApp e ele quer ser chamado no mesmo número.',
                   required: false

  ID = 'levar_ao_canal'.freeze

  SEM_CONVERSA = 'Não consegui identificar a conversa.'.freeze
  PEDIR_NUMERO = 'Falta o número de WhatsApp do cliente. Peça o número completo, com DDD, e chame de novo.'.freeze
  INDISPONIVEL = 'Não foi possível chamar o cliente por esse canal agora. Siga o atendimento por aqui, ou ofereça passar ' \
                 'a conversa para uma pessoa do time — sem informar número de telefone.'.freeze
  # Recusas viram orientação de conduta (o texto entra no contexto do agente).
  RECUSAS = {
    telefone_invalido: 'O número não parece válido. Confirme com o cliente o número completo de WhatsApp, com DDD, ' \
                       'antes de tentar de novo.',
    sem_contexto: 'Falta dizer por que o cliente está sendo chamado. Descreva o motivo e tente de novo.',
    convite_recente: 'Já foi enviada uma mensagem de abertura a partir desta conversa há pouco. Oriente o cliente a ' \
                     'conferir o WhatsApp.',
    mesmo_canal: 'O cliente já está neste canal. Siga o atendimento por aqui.'
  }.freeze

  # Caixas para onde a conversa desta caixa pode ir.
  def self.destinos(inbox)
    unidade = ::Unit.da_caixa(inbox)
    return [] unless unidade

    unidade.inboxes.select { |caixa| caixa.id != inbox.id && (caixa.canal_destino? || caixa.whatsapp_principal?) }
  end

  def self.armada?(assistant)
    Array(assistant.config&.dig('tools')).map(&:to_s).include?(ID)
  end

  def active?
    Inbox.where(account_id: @assistant.account_id)
         .exists?(["additional_attributes -> 'canal' ->> 'destino' = 'true' OR additional_attributes -> 'canal' ->> 'principal' = 'true'"])
  rescue StandardError => e
    Rails.logger.warn("[LevarAoCanal] active? indisponível: #{e.class} #{e.message}")
    false
  end

  def perform(tool_context, canal:, motivo:, telefone: nil)
    conversation = find_conversation(tool_context&.state)
    return SEM_CONVERSA unless conversation

    destinos = self.class.destinos(conversation.inbox)
    destino = destinos.find { |caixa| ::Unit.normalizar(caixa.name) == ::Unit.normalizar(canal) }
    return lista(destinos, canal) unless destino

    numero = numero_do_cliente(conversation, telefone)
    return PEDIR_NUMERO if numero.blank?

    levar(conversation, destino, numero, motivo)
  end

  private

  # O que o cliente informou nesta conversa; sem isso, o número que ele já tem no cadastro.
  def numero_do_cliente(conversation, telefone)
    telefone.to_s.strip.presence || conversation.contact&.phone_number
  end

  def levar(conversation, destino, numero, motivo)
    result = Whatsapp::ContactInviteService.new(conversation: conversation, phone: numero, contexto: motivo, destino: destino).perform
    log_tool_usage(ID, { conversation_id: conversation.id, destino: destino.id, ok: result.ok, error: result.error })
    return RECUSAS.fetch(result.error, INDISPONIVEL) unless result.ok

    "Mensagem de abertura enviada ao cliente pelo canal #{destino.name}; o atendimento continua lá. Diga com suas " \
      'palavras que ele vai receber a mensagem por lá. Não informe número de telefone.'
  end

  def lista(destinos, pedido)
    return 'Não há outro canal configurado para onde levar este cliente. Siga o atendimento por aqui.' if destinos.empty?

    nomes = destinos.map { |caixa| "\"#{caixa.name}\"" }.join(', ')
    "\"#{pedido}\" não é um dos canais de destino. Canais disponíveis: #{nomes}. Chame de novo com um deles."
  end
end
