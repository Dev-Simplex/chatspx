# Validacao por console da engine de disparo de campanhas WhatsApp (Fase 0).
# Replicavel: nada hardcoded — recebe account/inbox/template/time + uma lista CSV.
#
#   bundle exec rails 'campaigns:blast:create[<account_id>,<inbox_id>,<template_name>,<team_id>,<csv_path>,<titulo>]'
#   bundle exec rails 'campaigns:blast:start[<campaign_id>]'      # vira RUNNING (scheduler 1/min despacha)
#   bundle exec rails 'campaigns:blast:tick'                      # forca um tick agora (sem esperar o cron)
#   bundle exec rails 'campaigns:blast:status[<campaign_id>]'     # progresso por status
#   bundle exec rails 'campaigns:blast:pause[<campaign_id>]'
#
# CSV: cabecalho com colunas `nome` (ou name) e `telefone` (ou phone).
namespace :campaigns do
  namespace :blast do
    desc 'Cria uma campanha de disparo WhatsApp (draft) e carrega a lista. [account_id,inbox_id,template_name,team_id,csv_path,titulo]'
    task :create, %i[account_id inbox_id template_name team_id csv_path titulo] => :environment do |_t, args|
      require 'csv'
      account = Account.find(Integer(args[:account_id]))
      inbox = account.inboxes.find(Integer(args[:inbox_id]))
      csv_path = args[:csv_path].to_s
      raise "CSV nao encontrado: #{csv_path.inspect}" unless File.exist?(csv_path)

      campaign = account.campaigns.create!(
        title: args[:titulo].presence || "Disparo #{Time.current.strftime('%d/%m %H:%M')}",
        message: args[:template_name], inbox: inbox,
        template_name: args[:template_name], template_language: 'pt_BR',
        target_team_id: args[:team_id].presence && Integer(args[:team_id]),
        dispatch_status: :draft
      )

      rows = CSV.read(csv_path, headers: true).map(&:to_h)
      inserted = Campaigns::Whatsapp::ListLoaderService.new(campaign: campaign, rows: rows).perform

      puts "== Campanha ##{campaign.id} '#{campaign.title}' criada (draft) =="
      puts "   inbox=#{inbox.id} template=#{campaign.template_name} time=#{campaign.target_team_id || '-'}"
      puts "   destinatarios carregados: #{inserted} (de #{rows.size} linhas; dedup/invalidos descartados)"
      puts "   proximo: bundle exec rails 'campaigns:blast:start[#{campaign.id}]'"
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
