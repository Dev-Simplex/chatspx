# Carga e inspeção das unidades de uma conta — contrato em docs/contratos/unidades.md.
# Fase 1 não tem tela: endereço muda uma vez por ano e entra por aqui.
#
#   bundle exec rails "spx:unidades:carregar[7,/tmp/unidades.csv]"
#   bundle exec rails "spx:unidades:listar[7]"
#   bundle exec rails "spx:unidades:excecao[7,etiqueta:mt,2026-08-23,2026-08-23,09:00-15:00,campanha]"
#   bundle exec rails "spx:unidades:excecoes[7]"
#
# ── CSV (com cabeçalho) ────────────────────────────────────────────────────────────────────
#   slug,nome,cidade,uf,endereco,telefone,timezone,etiquetas,atributos,ativa,dom,seg,ter,qua,qui,sex,sab
#
#   etiquetas  lista separada por "|"
#   atributos  JSON (começando com "{") ou pares chave=valor separados por ";"
#   ativa      false/nao/0 desativa a unidade; qualquer outra coisa (ou vazio) mantém ativa
#   dias       "08:00-18:00", grade partida com "|" ("08:00-12:00|14:00-18:00"), ou "fechada"
#
#   ⚠️ Célula VAZIA e a palavra "fechada" são coisas DIFERENTES: vazia = dia não cadastrado (a
#   tool responde "não sei"), "fechada" = dia cadastrado como fechado. Confundir as duas é como
#   se inventa horário pro cliente.
#
#   A carga SUBSTITUI a grade semanal inteira da unidade — o CSV é a verdade, não um patch.
#
# Os helpers vivem num módulo em vez de virarem métodos soltos no topo: método definido dentro de
# um bloco de rake cai em Object e passa a existir pra todas as tasks do projeto.
module SpxUnidadesCarga
  DIAS = { 'dom' => 0, 'seg' => 1, 'ter' => 2, 'qua' => 3, 'qui' => 4, 'sex' => 5, 'sab' => 6 }.freeze

  module_function

  def atributos(bruto)
    texto = bruto.to_s.strip
    return {} if texto.blank?
    return JSON.parse(texto) if texto.start_with?('{')

    texto.split(';').each_with_object({}) do |par, acc|
      chave, valor = par.split('=', 2)
      acc[chave.to_s.strip] = valor.to_s.strip if chave.present?
    end
  end

  def criar_horarios(unidade, dia_semana, celula)
    texto = celula.to_s.strip
    return if texto.blank?

    if texto.downcase.start_with?('fechad')
      unidade.horarios.create!(dia_semana: dia_semana, fechada: true)
      return
    end

    texto.split('|').each do |faixa|
      abre, fecha = faixa.split('-').map(&:strip)
      unidade.horarios.create!(dia_semana: dia_semana, abre: abre, fecha: fecha, fechada: false)
    end
  end

  def aplicar_estado(excecao, bruto)
    estado = bruto.to_s.strip.downcase
    return excecao.fechada = true if estado.start_with?('fechad')
    # "normal" (ou vazio) = abre no horário de sempre. Serve pra uma unidade escapar de um
    # fechamento de etiqueta ou de conta inteira sem repetir a grade.
    return if estado.blank? || estado == 'normal'

    abre, fecha = estado.split('-').map(&:strip)
    excecao.assign_attributes(fechada: false, abre: abre, fecha: fecha)
  end

  def grade(unidade)
    Spx::Unidade::ORDEM_LEITURA.map do |dia_semana|
      faixas = unidade.faixas_padrao(dia_semana).map(&:to_s)
      cadastrado = unidade.horarios.any? { |horario| horario.dia_semana == dia_semana }
      "#{DIAS.key(dia_semana)} #{faixas.presence&.join(' e ') || (cadastrado ? 'fechada' : '—')}"
    end.join(' · ')
  end
end

# Metrics/BlockLength desligado no arquivo inteiro pelo mesmo motivo do spx_distribuicao.rake:
# o bloco é o DSL do rake, não lógica, e quebrar em métodos deixaria um script de config pior.
# rubocop:disable Metrics/BlockLength
namespace :spx do
  namespace :unidades do
    desc 'Carrega/atualiza as unidades de uma conta a partir de um CSV (idempotente por slug)'
    task :carregar, %i[account_id caminho] => :environment do |_t, args|
      require 'csv'
      account_id = args[:account_id].to_i
      linhas = CSV.read(args[:caminho].to_s, headers: true, encoding: 'bom|utf-8')
      criadas = 0
      atualizadas = 0

      linhas.each do |linha|
        slug = linha['slug'].to_s.strip
        if slug.blank?
          puts "  ignorada: linha sem slug (#{linha['nome']})"
          next
        end

        unidade = Spx::Unidade.find_or_initialize_by(account_id: account_id, slug: slug)
        nova = unidade.new_record?
        unidade.assign_attributes(
          nome: linha['nome'].presence || slug,
          cidade: linha['cidade'].presence,
          uf: linha['uf'].presence,
          endereco: linha['endereco'].presence,
          telefone: linha['telefone'].presence,
          timezone: linha['timezone'].presence || Spx::Unidade::FUSO_PADRAO,
          etiquetas: linha['etiquetas'].to_s.split('|').map(&:strip).compact_blank,
          atributos: SpxUnidadesCarga.atributos(linha['atributos']),
          ativa: !%w[false nao não 0].include?(linha['ativa'].to_s.strip.downcase)
        )
        unidade.save!

        unidade.horarios.delete_all
        SpxUnidadesCarga::DIAS.each { |coluna, dia| SpxUnidadesCarga.criar_horarios(unidade, dia, linha[coluna]) }

        nova ? criadas += 1 : atualizadas += 1
        puts "OK #{unidade.slug.ljust(20)} #{unidade.nome.to_s.ljust(28)} #{unidade.cidade}/#{unidade.uf} " \
             "ativa=#{unidade.ativa} horarios=#{unidade.horarios.count}"
      end

      puts "\n#{criadas} criada(s), #{atualizadas} atualizada(s) na conta #{account_id}."
    end

    desc 'Lista as unidades da conta com a grade semanal cadastrada'
    task :listar, %i[account_id] => :environment do |_t, args|
      unidades = Spx::Unidade.where(account_id: args[:account_id].to_i).includes(:horarios).order(:cidade, :nome)
      if unidades.empty?
        puts 'sem unidade cadastrada → a tool buscar_unidades não entra no toolset de agente nenhum'
        next
      end

      unidades.each do |unidade|
        puts "#{unidade.ativa ? '  ' : 'x '}#{unidade.slug.to_s.ljust(20)} #{unidade.nome.to_s.ljust(28)} " \
             "#{unidade.cidade}/#{unidade.uf} etiquetas=#{unidade.etiquetas.inspect}"
        puts "     #{SpxUnidadesCarga.grade(unidade)}"
      end
    end

    desc 'Cria exceção datada. alvo = slug:<slug> | etiqueta:<nome> | conta ; estado = fechada | HH:MM-HH:MM | normal'
    task :excecao, %i[account_id alvo data_inicio data_fim estado motivo] => :environment do |_t, args|
      account_id = args[:account_id].to_i
      inicio = args[:data_inicio].presence
      if inicio.blank?
        puts 'informe ao menos data_inicio (AAAA-MM-DD)'
        next
      end

      tipo, valor = args[:alvo].to_s.split(':', 2)
      excecao = Spx::UnidadeExcecao.new(account_id: account_id, motivo: args[:motivo].presence,
                                        data_inicio: Date.parse(inicio),
                                        data_fim: Date.parse(args[:data_fim].presence || inicio))

      case tipo
      when 'slug' then excecao.unidade_id = Spx::Unidade.find_by!(account_id: account_id, slug: valor.to_s.strip).id
      when 'etiqueta' then excecao.etiqueta = valor.to_s.strip
      when 'conta' then nil
      else
        puts "alvo inválido: #{args[:alvo].inspect} (use slug:<slug>, etiqueta:<nome> ou conta)"
        next
      end

      SpxUnidadesCarga.aplicar_estado(excecao, args[:estado])
      excecao.save!
      puts "OK excecao ##{excecao.id} conta=#{account_id} unidade=#{excecao.unidade_id.inspect} " \
           "etiqueta=#{excecao.etiqueta.inspect} #{excecao.data_inicio}..#{excecao.data_fim} " \
           "fechada=#{excecao.fechada} #{excecao.abre&.strftime('%H:%M')}-#{excecao.fecha&.strftime('%H:%M')} " \
           "motivo=#{excecao.motivo.inspect} especificidade=#{excecao.especificidade}"
    end

    desc 'Lista as exceções que ainda não venceram (as vencidas morrem sozinhas, é o ponto do desenho)'
    task :excecoes, %i[account_id] => :environment do |_t, args|
      excecoes = Spx::UnidadeExcecao.where(account_id: args[:account_id].to_i)
                                    .a_partir_de(Time.zone.today).order(:data_inicio, :id)
      if excecoes.empty?
        puts 'sem exceção futura'
        next
      end

      excecoes.each do |excecao|
        alvo = if excecao.unidade_id.present?
                 "unidade=#{excecao.unidade_id}"
               else
                 excecao.etiqueta.presence ? "etiqueta=#{excecao.etiqueta}" : 'conta inteira'
               end
        janela = excecao.fechada ? 'FECHADA' : "#{excecao.abre&.strftime('%H:%M')}-#{excecao.fecha&.strftime('%H:%M')}"
        puts "##{excecao.id} #{excecao.data_inicio}..#{excecao.data_fim} #{alvo.ljust(26)} #{janela.ljust(14)} #{excecao.motivo}"
      end
    end
  end
end
# rubocop:enable Metrics/BlockLength
