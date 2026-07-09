module Campaigns
  module Whatsapp
    # Scheduler RESUMIVEL do disparo de campanhas WhatsApp. Roda a cada minuto
    # (config/schedule.yml) e, para cada campanha em `dispatch_running`:
    #
    #   1. respeita quiet-hours e o gate de saude do numero (opt-in),
    #   2. reivindica um lote de pendentes proporcional ao pacing,
    #   3. despacha via RecipientDispatchService,
    #   4. conclui a campanha quando a fila de pendentes esvazia.
    #
    # A fonte de verdade e a tabela campaign_recipients (status), nao a fila do
    # Sidekiq: pausar = `dispatch_paused!`; retomar = `dispatch_running!` (segue
    # de onde parou). A reivindicacao atomica (CampaignRecipient#claim!) torna
    # ticks concorrentes seguros contra duplicata.
    class DispatchSchedulerJob < ApplicationJob
      queue_as :scheduled_jobs

      MAX_BATCH = 200

      def perform
        @quality_by_inbox = {}
        Campaign.dispatch_running.where(campaign_type: :one_off).find_each(batch_size: 50) do |campaign|
          next unless campaign.whatsapp_blast?

          process_campaign(campaign)
        end
      end

      private

      def process_campaign(campaign)
        return complete_if_drained(campaign) unless campaign.campaign_recipients.pending.exists?
        return if quiet_hours?(campaign)
        return unless health_ok?(campaign)

        claim_batch(campaign, batch_size(campaign)).each do |recipient|
          RecipientDispatchService.new(recipient: recipient).perform
        end
        complete_if_drained(campaign)
      end

      # Quantos enviar neste tick (1/min) dado o pacing em segundos.
      def batch_size(campaign)
        per_minute = 60 / [campaign.pacing_seconds.to_i, 1].max
        [[per_minute, 1].max, MAX_BATCH].min
      end

      def claim_batch(campaign, limit)
        campaign.campaign_recipients.pending.order(:id).limit(limit).select(&:claim!)
      end

      def complete_if_drained(campaign)
        return if campaign.campaign_recipients.where(status: %i[pending processing]).exists?

        campaign.dispatch_completed!
      end

      def quiet_hours?(campaign)
        cfg = campaign.dispatch_config['quiet_hours']
        return false if cfg.blank?

        tz = campaign.account.timezone.presence || 'UTC'
        hour = Time.current.in_time_zone(tz).hour
        start_h = cfg['start'].to_i
        end_h = cfg['end'].to_i
        # Janela que cruza a meia-noite (ex.: 21->8) vs. janela no mesmo dia.
        start_h > end_h ? (hour >= start_h || hour < end_h) : (hour >= start_h && hour < end_h)
      end

      def health_ok?(campaign)
        return true unless campaign.dispatch_config['health_gate']

        quality = (@quality_by_inbox[campaign.inbox_id] ||= fetch_quality(campaign.inbox.channel))
        quality != 'RED'
      end

      def fetch_quality(channel)
        health = ::Whatsapp::HealthService.new(channel).fetch_health_status
        (health['quality_rating'] || health[:quality_rating]).to_s.presence
      rescue StandardError => e
        Rails.logger.warn("[CampaignDispatch] health check inbox falhou: #{e.message}")
        nil # desconhecido -> nao bloqueia
      end
    end
  end
end
