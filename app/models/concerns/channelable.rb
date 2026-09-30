module Channelable
  extend ActiveSupport::Concern
  included do
    validates :account_id, presence: true
    belongs_to :account
    has_one :inbox, as: :channel, dependent: :destroy_async, touch: true
    after_update :create_audit_log_entry
  end

  def create_audit_log_entry; end

  # O canal entrega o objeto `interactive` da Meta que a mensagem carrega em
  # content_attributes['interactive_payload'] (carrossel, cta_url, location_request, Flow)?
  # Só o WhatsApp Cloud lê essa chave — quem não lê NÃO falha: manda o `content` como texto
  # comum e a mensagem sai vazia de conteúdo real, sem erro em lugar nenhum. Por isso a
  # pergunta precisa ser feita por quem MONTA o payload, antes de montá-lo.
  def supports_interactive_payload?
    false
  end

  # O canal transforma `content_type: input_select` + content_attributes['items'] em menu
  # (botões/lista/quick replies)? É a MESMA armadilha da pergunta acima, uma camada abaixo:
  # quem não implementa não falha, manda só o `content` e as opções somem — a pessoa recebe
  # uma pergunta sem resposta possível.
  #
  # Falso por padrão de propósito. Errar para o `false` custa um passo `skipped` triável no
  # Flow; errar para o `true` custa uma mensagem muda no cliente. Canal novo entra aqui de
  # forma explícita, junto do código que de fato desenha o menu.
  def supports_interactive_items?
    false
  end

  # O canal entrega VÁRIAS imagens numa única mensagem? Quem não entrega manda uma
  # requisição por anexo, como sempre — a pergunta só troca o empacotamento do envio,
  # não o que é enviado.
  def supports_multi_image_message?
    false
  end

  # O canal desenha a vitrine de cards que a mensagem carrega em content_attributes['cards']
  # (título, foto, subtítulo e um botão por card)? A lista é AGNÓSTICA de propósito: cada
  # canal a traduz pro formato dele. Quem não desenha NÃO falha — manda o `content` como
  # texto —, então, como no interactive_payload, a pergunta precisa ser feita por quem MONTA
  # a lista, antes de montá-la.
  def supports_card_carousel?
    false
  end

  # O canal permite RETOMAR a conversa depois que a janela de atendimento fecha? O WhatsApp
  # permite (template/HSM), o widget e a Api nao tem janela — o Instagram e a excecao: nao
  # existe template, sponsored message nem one-time notification, e a unica extensao da janela
  # de 24h e a tag HUMAN_AGENT, que depende de App Review (medido em 08/09/2026 contra a Graph:
  # 403 "To use 'Human Agent', your use of this endpoint must be reviewed and approved").
  #
  # Verdadeiro por padrao de proposito, ao contrario das capacidades acima: aqui o custo esta
  # invertido. Errar para o `false` faz o agente pedir contato alternativo a quem ele ja alcanca
  # — barulho em canal que nao precisa; errar para o `true` so mantem o comportamento atual.
  def supports_reengagement?
    true
  end
end

Channelable.prepend_mod_with('Channelable')
