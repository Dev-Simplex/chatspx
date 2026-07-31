# Operacao por console da engine de disparo de campanhas WhatsApp.
# Replicavel: nada hardcoded — recebe account/inbox/template/time + uma lista CSV.
#
#   bundle exec rails 'campaigns:blast:create[<account_id>,<inbox_id>,<template_name>,<team_id>,<csv_path>,<titulo>]'
#   bundle exec rails 'campaigns:blast:preview[<campaign_id>,<csv_path>]'  # dry-run: quem entra, quem sai, por que
#   bundle exec rails 'campaigns:blast:owner[<campaign_id>,<user_id>]'     # dono do disparo (atende as respostas)
#   bundle exec rails 'campaigns:blast:start[<campaign_id>]'      # vira RUNNING (scheduler 1/min despacha)
#   bundle exec rails 'campaigns:blast:tick'                      # forca um tick agora (sem esperar o cron)
#   bundle exec rails 'campaigns:blast:status[<campaign_id>]'     # progresso por status
#   bundle exec rails 'campaigns:blast:pause[<campaign_id>]'
#
# CSV: cabecalho com colunas `nome` (ou name) e `telefone` (ou phone). O caminho
# pode ser um DIRETORIO — todos os .csv dele entram como uma audiencia so, com
# deduplicacao entre arquivos (caso comum: a campanha chega em varias planilhas).
namespace :campaigns do
  namespace :blast do
    # Le um CSV ou todos os CSVs de um diretorio.
    def blast_rows(path)
      require 'csv'
      raise "Lista nao encontrada: #{path.inspect}" unless File.exist?(path)

      files = File.directory?(path) ? Dir.glob(File.join(path, '*.csv')) : [path]
      raise "Nenhum .csv em #{path.inspect}" if files.empty?

      files.flat_map { |file| CSV.read(file, headers: true).map(&:to_h) }
    end

    # Relatorio da higiene da audiencia: o total, os aceitos e o motivo de CADA descarte.
    def print_audience(result)
      stats = result.stats
      puts "   linhas lidas: #{stats[:total]} | aceitos: #{stats[:aceitos]} | descartados: #{stats[:descartados]}"
      stats[:por_motivo].each { |reason, count| puts "     - #{reason.to_s.ljust(20)} #{count}" }
      return if result.rejected.empty?

      puts '   amostra de descartes:'
      result.rejected.first(5).each { |r| puts "     #{r[:phone].to_s.ljust(20)} #{r[:reason]}" }
    end

    desc 'Cria uma campanha de disparo WhatsApp (draft) e carrega a lista. [account_id,inbox_id,template_name,team_id,csv_path,titulo]'
    task :create, %i[account_id inbox_id template_name team_id csv_path titulo] => :environment do |_t, args|
      account = Account.find(Integer(args[:account_id]))
      inbox = account.inboxes.find(Integer(args[:inbox_id]))
      rows = blast_rows(args[:csv_path].to_s)

      campaign = account.campaigns.create!(
        title: args[:titulo].presence || "Disparo #{Time.current.strftime('%d/%m %H:%M')}",
        message: args[:template_name], inbox: inbox,
        template_name: args[:template_name], template_language: 'pt_BR',
        target_team_id: args[:team_id].presence && Integer(args[:team_id]),
        dispatch_status: :draft
      )

      result = Campaigns::Whatsapp::ListLoaderService.new(campaign: campaign, rows: rows).perform

      puts "== Campanha ##{campaign.id} '#{campaign.title}' criada (draft) =="
      puts "   inbox=#{inbox.id} template=#{campaign.template_name} time=#{campaign.target_team_id || '-'}"
      print_audience(result)
      puts "   destinatarios gravados: #{result.stats[:inseridos]}"
      puts "   proximo: bundle exec rails 'campaigns:blast:start[#{campaign.id}]'"
    end

    desc 'Dry-run da audiencia: quem entra, quem sai e por que — sem gravar nada. [campaign_id,csv_path]'
    task :preview, %i[campaign_id csv_path] => :environment do |_t, args|
      campaign = Campaign.find(Integer(args[:campaign_id]))
      rows = blast_rows(args[:csv_path].to_s)
      result = Campaigns::Whatsapp::AudienceBuilderService.new(campaign: campaign, rows: rows).perform

      puts "== Preview da audiencia — campanha ##{campaign.id} '#{campaign.title}' (NADA foi gravado) =="
      print_audience(result)
    end

    desc 'Define o dono do disparo: quem atende as respostas desta campanha. [campaign_id,user_id]'
    task :owner, %i[campaign_id user_id] => :environment do |_t, args|
      campaign = Campaign.find(Integer(args[:campaign_id]))
      campaign.update!(dispatch_assignee_id: args[:user_id].presence && Integer(args[:user_id]))
      owner = campaign.reload.dispatch_assignee

      puts "== Campanha ##{campaign.id} — dono do disparo: #{owner ? "#{owner.name} (##{owner.id})" : 'nenhum'} =="
      puts '   A atribuicao acontece quando o lead RESPONDE (nao no envio).'
      puts '   ATENCAO: nao use em inbox com IA — atribuir humano cala o agente.' if owner
    end

    desc 'Inicia/retoma o disparo (vira RUNNING). [campaign_id]'
    task :start, [:campaign_id] => :environment do |_t, args|
      campaign = Campaign.find(Integer(args[:campaign_id]))
      campaign.dispatch_running!
      pending = campaign.campaign_recipients.pending.count
      puts "== Campanha ##{campaign.id} em RUNNING — #{pending} pendentes; o scheduler (1/min) vai despachar no pacing de #{campaign.pacing_seconds}s =="
    end

    desc 'Pausa o disparo (mantem os pendentes). [campaign_id]'
    task :pause, [:campaign_id] => :environment do |_t, args|
      Campaign.find(Integer(args[:campaign_id])).dispatch_paused!
      puts '== pausado (retomar com start) =='
    end

    desc 'Forca um tick do scheduler agora (teste sem esperar o cron).'
    task tick: :environment do
      Campaigns::Whatsapp::DispatchSchedulerJob.perform_now
      puts '== tick executado =='
    end

    desc 'Progresso do disparo por status. [campaign_id]'
    task :status, [:campaign_id] => :environment do |_t, args|
      campaign = Campaign.find(Integer(args[:campaign_id]))
      counts = campaign.campaign_recipients.group(:status).count
      puts "== Campanha ##{campaign.id} '#{campaign.title}' — dispatch=#{campaign.dispatch_status} =="
      CampaignRecipient.statuses.each_key { |s| puts "   #{s.ljust(12)} #{counts[s].to_i}" }
    end
  end
end
