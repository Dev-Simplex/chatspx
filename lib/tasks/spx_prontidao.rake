# Diagnostico de PRONTIDAO de uma conta — so leitura, nenhum UPDATE.
#
#   bundle exec rails spx:prontidao:conta          # todas as contas da instalacao
#   bundle exec rails "spx:prontidao:conta[5]"     # so a conta 5
#
# Cada implantacao nova e cada auditoria repetiam as mesmas consultas a mao: caixa sem atendente,
# caixa WAHA sem sessao, time recebendo conversa sem ninguem dentro, conversa sem dono onde o rodizio
# nao esta ligado, conversa parada ha semanas sem encerramento automatico, "esperando" que ja foi
# respondido pelo celular, e IA configurada pela metade. Isto e essa lista, em um comando.
#
# Espelha Message::WHATSAPP_PHONE_REPLY_MARKER (N-01). Repetido aqui DE PROPOSITO: o diagnostico
# precisa rodar tambem nas VMs que ainda nao receberam aquele PR.
MARCADOR_RESPOSTA_CELULAR = '*📱 Enviado do WhatsApp*'.freeze
DIAS_PARADA = 30

module SpxProntidao
  ABERTAS = %w[open pending].freeze

  def self.achados(conta)
    [
      caixas_sem_atendente(conta), caixas_waha_sem_sessao(conta), times_sem_ninguem(conta),
      sem_dono_sem_rodizio(conta), paradas_sem_encerramento(conta), esperando_respondida_no_celular(conta),
      ia_pela_metade(conta)
    ]
  end

  # Caixa sem membro nenhum: a conversa entra e nao aparece para ninguem.
  def self.caixas_sem_atendente(conta)
    caixas = conta.inboxes.where.missing(:inbox_members)
    ['caixa sem atendente', caixas.map { |i| "##{i.id} #{i.name}" }]
  end

  # Caixa que RECEBE WhatsApp e esta sem sessao WAHA: o envio sai com 404 e ninguem percebe. O sinal de
  # "isto aqui e WhatsApp" e o identificador do contato — telefone ou @c.us/@g.us. Caixa de API comum
  # (widget, integracao) usa UUID e fica de fora, senao o diagnostico acusaria o que esta certo.
  TRAFEGO_WHATSAPP = "source_id ~ '^[0-9]{8,}(@[cg]\\.us)?$'".freeze

  def self.caixas_waha_sem_sessao(conta)
    caixas = conta.inboxes.where(channel_type: 'Channel::Api').where(waha_session_name: [nil, ''])
                  .select { |i| i.contact_inboxes.where(TRAFEGO_WHATSAPP).exists? }
    ['caixa WAHA sem sessao', caixas.map { |i| "##{i.id} #{i.name}" }]
  end

  # Time que recebe conversa e nao tem ninguem dentro: o lead fica num limbo com nome.
  def self.times_sem_ninguem(conta)
    times = conta.teams.where.missing(:team_members)
    achados = times.filter_map do |time|
      abertas = conta.conversations.where(team_id: time.id, status: ABERTAS).count
      "##{time.id} #{time.name} (#{abertas} abertas)" if abertas.positive?
    end
    ['time recebendo sem ninguem dentro', achados]
  end

  # Conversa aberta sem dono num time sem politica ativa: nao ha quem distribua, e ela so espera.
  def self.sem_dono_sem_rodizio(conta)
    com_rodizio = Spx::Distribuicao::Policy.where(account_id: conta.id, ativo: true).pluck(:team_id)
    por_time = conta.conversations.where(status: ABERTAS, assignee_id: nil).where.not(team_id: nil)
                    .where.not(team_id: com_rodizio).group(:team_id).count
    nomes = conta.teams.where(id: por_time.keys).pluck(:id, :name).to_h
    ['conversa sem dono, sem rodizio ligado', por_time.map { |time_id, total| "##{time_id} #{nomes[time_id]} (#{total})" }]
  end

  # Conversa parada ha semanas. Com encerramento automatico configurado isto se resolve sozinho; sem ele,
  # a fila so cresce e as metricas de "em aberto" mentem.
  def self.paradas_sem_encerramento(conta)
    paradas = conta.conversations.where(status: ABERTAS).where(last_activity_at: ..DIAS_PARADA.days.ago).count
    return ['conversa parada ha mais de 30 dias', []] if paradas.zero?

    auto = conta.auto_resolve_duration
    detalhe = auto.present? ? "encerramento automatico em #{auto} dias" : 'SEM encerramento automatico'
    ["conversa parada ha mais de #{DIAS_PARADA} dias", ["#{paradas} conversas — #{detalhe}"]]
  end

  # "Esperando" que ja foi respondida pelo celular (a ponte grava como nota privada). Enquanto a N-01 nao
  # entrar, essas conversas mentem no filtro de nao atendidas e no tempo de primeira resposta.
  def self.esperando_respondida_no_celular(conta)
    esperando = conta.conversations.where(status: ABERTAS).where.not(waiting_since: nil)
    total = esperando.count
    return ['"esperando" ja respondida pelo celular', []] if total.zero?

    com_resposta = Message.where(conversation_id: esperando.select(:id), private: true, message_type: :outgoing)
                          .where('content LIKE ?', "#{MARCADOR_RESPOSTA_CELULAR}%")
                          .distinct.count(:conversation_id)
    achado = com_resposta.positive? ? ["#{com_resposta} de #{total} esperando ja tiveram resposta pelo celular"] : []
    ['"esperando" ja respondida pelo celular', achado]
  end

  # IA configurada pela metade: assistente que nao atende caixa nenhuma, ou caixa com IA que nao responde
  # ha uma semana (chave invalida, cota estourada, prompt quebrado).
  def self.ia_pela_metade(conta)
    return ['IA configurada pela metade', []] unless defined?(Captain::Assistant)

    assistentes = Captain::Assistant.where(account_id: conta.id)
    return ['IA configurada pela metade', []] if assistentes.empty?

    sem_caixa = assistentes.reject { |a| CaptainInbox.exists?(captain_assistant_id: a.id) }
    achados = sem_caixa.map { |a| "assistente ##{a.id} #{a.name} nao atende caixa nenhuma" }
    caixas_com_ia = CaptainInbox.where(captain_assistant_id: assistentes.select(:id)).pluck(:inbox_id)
    calada = caixas_com_ia.any? &&
             !Message.where(inbox_id: caixas_com_ia, sender_type: 'Captain::Assistant')
                     .exists?(created_at: 7.days.ago..)
    achados << "#{caixas_com_ia.size} caixa(s) com IA ligada e nenhuma resposta dela em 7 dias" if calada
    ['IA configurada pela metade', achados]
  end
end

namespace :spx do
  namespace :prontidao do
    desc 'Diagnostico de prontidao por conta (so leitura). args: account_id opcional'
    task :conta, %i[account_id] => :environment do |_t, args|
      contas = args[:account_id].present? ? Account.where(id: args[:account_id].to_i) : Account.order(:id)
      problemas = 0

      contas.each do |conta|
        puts "\n=== conta #{conta.id} — #{conta.name} ==="
        SpxProntidao.achados(conta).each do |titulo, itens|
          if itens.empty?
            puts "  [ok] #{titulo}"
          else
            problemas += itens.size
            puts "  [!]  #{titulo}: #{itens.size}"
            itens.each { |item| puts "         #{item}" }
          end
        end
      end

      puts "\ntotal de pontos de atencao: #{problemas}"
    end
  end
end
