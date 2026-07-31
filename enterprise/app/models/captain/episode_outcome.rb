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

  # O corte da conversão. Só o que a IA de fato controla: visita e venda dependem
  # do corretor, então incluí-las mediria o time comercial, não o atendimento.
  DEGRAUS_CONVERSAO = %w[qualificado handoff].freeze

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

  # A métrica primária. Passa pelo do_spx por construção, não por convenção do chamador.
  scope :conversao, -> { do_spx.where(degrau: DEGRAUS_CONVERSAO) }
end
