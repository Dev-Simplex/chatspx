# Desfecho de um episódio (Eval 2.0 F3). Uma linha por degrau atingido — fato
# observado a partir de sinal determinístico, nunca veredito de LLM.
class Captain::EpisodeOutcome < ApplicationRecord
  self.table_name = 'captain_episode_outcomes'

  # Escada ascendente: o que queremos que aconteça.
  PROGRESSAO = %w[respondeu qualificado handoff assumido visita venda].freeze
  # Terminais negativos. 'esfriou' volta pro pool de reabordagem; 'descartado'
  # (nao_qualificado) NÃO é re-abordado — a distinção é o modelo quente/frio e
  # colapsar os dois destruiria a informação que protege contra erro de enquadramento.
  SAIDAS = %w[esfriou descartado].freeze
  DEGRAUS = (PROGRESSAO + SAIDAS).freeze

  # Degraus que PARTICIPAM da conversão — use só pra marcar/exibir. O filtro
  # autoritativo é o scope `conversao`, porque 'assumido' só conta com a IA tendo
  # atendido antes (ver lá).
  DEGRAUS_CONVERSAO = %w[qualificado assumido].freeze

  # Procedências que vêm de FORA do SPX. Ver o scope do_spx abaixo.
  ORIGENS_EXTERNAS = %w[vista].freeze

  AUTORES = %w[ia humano sistema contato externo].freeze

  belongs_to :account
  belongs_to :conversation, class_name: '::Conversation'
  belongs_to :episode, class_name: 'Captain::ConversationEpisode'

  validates :degrau, inclusion: { in: DEGRAUS }
  validates :causado_por, inclusion: { in: AUTORES }
  validates :ocorreu_em, presence: true
  validates :episode_id, uniqueness: { scope: :degrau }

  scope :for_account, ->(account_id) { where(account_id: account_id) }
  scope :progressao, -> { where(degrau: PROGRESSAO) }
  scope :por_campanha, ->(campanha) { where(campanha: campanha) }

  # 🔒 GUARD-RAIL (não remover sem decisão explícita): o corretor não alimenta o CRM
  # com disciplina. Se o status do Vista entrar na métrica primária, o painel passa a
  # medir a disciplina de CRM do corretor, não a qualidade do atendimento. O dado
  # externo existe pra CORRELAÇÃO e ATRIBUIÇÃO — nunca somado à conversão.
  scope :do_spx, -> { where.not(origem: ORIGENS_EXTERNAS) }
  scope :externos, -> { where(origem: ORIGENS_EXTERNAS) }

  # 'assumido' com a IA tendo conduzido antes. Sem esse qualificador, atendimento que
  # SEMPRE foi humano viraria conversão da IA — e ele é maioria: no dry-run da conta 6,
  # 248 dos 342 assumidos eram só-humano.
  scope :assumido_com_ia, lambda {
    where(degrau: 'assumido').where('detalhe @> ?', { ia_atendia_antes: true }.to_json)
  }
  scope :assumido_so_humano, lambda {
    where(degrau: 'assumido').where.not('detalhe @> ?', { ia_atendia_antes: true }.to_json)
  }

  # A métrica primária — CORTE B, decidido em 31/07 sobre o dry-run da conta 6 e
  # MANTIDO em 02/08, depois de o `handoff` virar degrau durável (`0f320f967`).
  #
  # Por que 'handoff' segue FORA do corte, mesmo agora que é durável:
  #  1. O evento nasceu em 31/07. Entrar no corte criaria um DEGRAU NA SÉRIE exatamente
  #     na data do deploy — a conversão saltaria por motivo instrumental, não por
  #     conduta, e envenenaria a medição antes/depois que está sendo montada.
  #  2. Handoff sem ninguém pegar é entrega que morreu na fila: é falha de operação,
  #     não conversão. Somá-lo inflaria o número com o que o time NÃO atendeu.
  # O degrau continua sendo gravado e exibido na escada — a distância entre `handoff` e
  # `assumido` é justamente o SLA de pickup que a frente spx/rodizio persegue.
  #
  # 'assumido' vem de mensagem + log human_takeover, duráveis desde sempre; os dois
  # cortes deram praticamente o mesmo número (23,4% × 24,2%).
  #
  # Passa pelo do_spx por construção, não por convenção do chamador.
  scope :conversao, lambda {
    do_spx.where(degrau: 'qualificado').or(do_spx.assumido_com_ia)
  }
end
