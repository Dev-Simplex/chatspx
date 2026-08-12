# Tela de campanhas de captação (fatia 1 — SÓ LEITURA).
#
# Responde a duas perguntas que hoje só se responde com SQL: *quais campanhas trouxeram
# lead no período* e *como cada uma está configurada*. Não escreve nada, não fala com a
# API de Ads da Meta e não conhece campanha que nunca gerou lead — tudo o que aparece
# aqui já existe no banco:
#
#   - o carimbo de origem na conversa (`custom_attributes.meta_campanha` e irmãos), que a
#     engine de captação grava em `stamp_campaign_visibility`;
#   - o template que DE FATO saiu, em `messages.additional_attributes.template_params.name`
#     (não em `content_attributes`, onde ele não está);
#   - a configuração viva do hook, resolvida por `LeadCampaigns::ConfigResolver`.
#
# Mostrar *configurado* e *enviado* lado a lado é o ponto da tela: quando divergem, ou o
# override entrou depois dos leads, ou o template configurado não existe mais no canal.
#
# AGNÓSTICO: nenhum nome de cliente, campanha ou template no código. Conta sem hook de
# captação recebe `habilitado: false` e não vê a tela.
#
# PERMISSÃO: volume por campanha todo mundo vê; **configuração de roteamento (template,
# agente, time, override, hooks) é só para admin**.
#
# Read-only e defensivo: seção que falhar volta vazia em vez de derrubar a tela.
class Api::V1::Accounts::LeadCampaignsController < Api::V1::Accounts::BaseController
  before_action :current_account

  # Marcador que a engine grava em `conversation.additional_attributes['source']`, para
  # qualquer origem de formulário. É o recorte do "lead de formulário" no banco.
  INTAKE_SOURCE = 'meta_lead_ads'.freeze

  DEFAULT_PERIOD_DAYS = 30
  # Teto do período: a consulta varre as conversas do intervalo linha a linha.
  MAX_PERIOD_DAYS = 366
  MAX_ROWS = 100

  # Nome da campanha como o time o vê no painel, com o registro do lead como reserva
  # para a conversa cujo carimbo não chegou a rodar.
  NOME_SQL = Arel.sql(
    "COALESCE(NULLIF(conversations.custom_attributes->>'meta_campanha', ''), " \
    "conversations.additional_attributes->'lead'->>'campaign_name')"
  ).freeze
  TIPO_SQL = Arel.sql("conversations.custom_attributes->>'meta_tipo'").freeze
  ORIGEM_SQL = Arel.sql("conversations.custom_attributes->>'meta_origem'").freeze
  TEMPLATE_NOME_SQL = Arel.sql("messages.additional_attributes->'template_params'->>'name'").freeze

  def show
    return render json: { habilitado: false, admin: admin?, campanhas: [], hooks: [] } unless config.any?

    render json: {
      habilitado: true,
      admin: admin?,
      periodo: { de: periodo.first, ate: periodo.last },
      hooks: admin? ? config.hooks_payload : [],
      campanhas: campanhas,
      totais: totais
    }
  end

  private

  def admin?
    Current.account_user&.administrator?
  end

  def config
    @config ||= LeadCampaigns::ConfigResolver.new(Current.account)
  end

  # ------------------------------------------------------------------ período

  def periodo
    @periodo ||= begin
      ate = parse_time(params[:ate]) || Time.zone.now.end_of_day
      de = parse_time(params[:de]) || (ate - DEFAULT_PERIOD_DAYS.days).beginning_of_day
      de = ate - MAX_PERIOD_DAYS.days if de > ate || (ate - de) > MAX_PERIOD_DAYS.days
      [de, ate]
    end
  end

  def parse_time(valor)
    valor.present? ? Time.zone.parse(valor.to_s) : nil
  rescue ArgumentError, TypeError
    nil
  end

  # ------------------------------------------------------------------ leitura

  def conversas
    @conversas ||= Current.account.conversations
                          .where(created_at: periodo.first..periodo.last)
                          .where("conversations.additional_attributes->>'source' = ?", INTAKE_SOURCE)
  end

  # Uma linha por conversa criada no período: [id, contact_id, campanha, tipo, origem].
  # Conversa reusada (o contato já tinha uma) fica de fora por definição — a unidade aqui
  # é "lead que abriu conversa no período", e é isso que a tela diz no subtítulo.
  def linhas
    @linhas ||= conversas.pluck(:id, :contact_id, NOME_SQL, TIPO_SQL, ORIGEM_SQL)
  rescue StandardError
    []
  end

  # Nome da campanha → id. O par (id, nome) é gravado JUNTO no contato, no momento em que
  # ele nasce; continua sendo um par válido mesmo depois que outra campanha reusa aquele
  # contato. Por isso ele serve de DICIONÁRIO nome→id, e nunca de atribuição por conversa
  # (o contato guarda a campanha da PRIMEIRA entrada, não a desta conversa).
  def dicionario_ids
    @dicionario_ids ||= begin
      contagem = Hash.new { |hash, chave| hash[chave] = Hash.new(0) }
      pares_campanha.each { |id, nome| contagem[nome][id] += 1 if id.present? && nome.present? }
      contagem
    end
  rescue StandardError
    {}
  end

  def pares_campanha
    Contact.where(account_id: Current.account.id, id: linhas.filter_map { |linha| linha[1] }.uniq)
           .pluck(Arel.sql("contacts.additional_attributes->>'campaign_id'"),
                  Arel.sql("contacts.additional_attributes->>'campaign_name'"))
  end

  # Template do PRIMEIRO disparo de cada conversa — o opener. Vale a primeira mensagem com
  # `template_params` porque a conversa nasceu no período: follow-up e reativação vêm depois.
  def template_por_conversa
    @template_por_conversa ||= begin
      escopo = Message.where(account_id: Current.account.id, conversation_id: conversas.select(:id))
                      .where("messages.additional_attributes->'template_params'->>'name' IS NOT NULL")
      # `reorder(nil)`: o default_scope de Message ordena por created_at, e o ORDER BY
      # sobrevive ao GROUP BY e quebra a agregação no Postgres.
      primeiras = escopo.reorder(nil).group(:conversation_id).minimum(:id)
      Message.where(id: primeiras.values).pluck(:conversation_id, TEMPLATE_NOME_SQL).to_h
    end
  rescue StandardError
    {}
  end

  # ------------------------------------------------------------------ linhas

  def campanhas
    observadas = linhas.group_by { |linha| linha[2].to_s.strip.presence }
    ordenadas = observadas.sort_by { |_nome, registros| -registros.size }
    linhas_observadas = ordenadas.first(MAX_ROWS).map { |nome, registros| linha_observada(nome, registros) }
    (linhas_observadas + linhas_sem_lead(observadas.keys)).first(MAX_ROWS)
  end

  def linha_observada(nome, registros)
    campaign_id, ambiguo = resolve_id(nome)
    linha = {
      nome: nome,
      campaign_id: campaign_id,
      id_ambiguo: ambiguo,
      leads: registros.size,
      tipos: contar(registros) { |registro| registro[3] },
      origens: contar(registros) { |registro| registro[4] },
      templates_enviados: templates_enviados(registros)
    }
    admin? ? linha.merge(config.para(campaign_id)) : linha
  end

  # Campanha configurada no hook que não trouxe lead no período entra com zero: a pergunta
  # "como esta campanha está configurada" continua valendo quando o volume é zero.
  def linhas_sem_lead(nomes_observados)
    return [] unless admin?

    ids_observados = nomes_observados.filter_map { |nome| resolve_id(nome).first }
    (config.campanhas_configuradas - ids_observados).map do |campaign_id|
      {
        nome: nil, campaign_id: campaign_id, id_ambiguo: false, leads: 0,
        tipos: {}, origens: {}, templates_enviados: []
      }.merge(config.para(campaign_id))
    end
  end

  # Nome com mais de um id no dicionário acontece quando a campanha é renomeada na Meta.
  # Vale o id mais frequente, e a linha diz que houve ambiguidade em vez de escondê-la.
  def resolve_id(nome)
    ids = dicionario_ids[nome]
    return [nil, false] if ids.blank?

    [ids.max_by { |_id, total| total }.first, ids.size > 1]
  end

  def templates_enviados(registros)
    mapa = template_por_conversa
    contagem = contar(registros) { |registro| mapa[registro[0]] }
    contagem.sort_by { |_nome, total| -total }.map { |nome, total| { nome: nome, leads: total } }
  end

  # Conta ocorrências ignorando o que veio vazio — dado sujo da origem não vira categoria.
  def contar(registros)
    registros.each_with_object(Hash.new(0)) do |registro, acc|
      chave = yield(registro).to_s.strip
      acc[chave] += 1 if chave.present?
    end
  end

  def totais
    { leads: linhas.size, campanhas: linhas.group_by { |linha| linha[2] }.size }
  end
end
