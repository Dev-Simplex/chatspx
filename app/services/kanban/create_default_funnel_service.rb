# frozen_string_literal: true

module Kanban
  class CreateDefaultFunnelService
    def initialize(account:)
      @account = account
    end

    def perform
      return nil unless @account.present?

      # Verificar se já existe funil padrão para este account (team_id = NULL)
      existing_funnel = Funnel.find_by(account_id: @account.id, team_id: nil)
      return existing_funnel if existing_funnel.present?

      ActiveRecord::Base.transaction do
        # Criar funil padrão com nome "Geral"
        funnel = Funnel.create!(
          name: 'Geral',
          account_id: @account.id,
          team_id: nil,
          position: 0,
          color: '#94a3b8'
        )

        # Criar etapa "Abertos" com automação
        FunnelStage.create!(
          name: 'Abertos',
          funnel_id: funnel.id,
          position: 0,
          color: '#10b981',
          automation_type: 'open'
        )

        # Criar etapa "Em Andamento"
        FunnelStage.create!(
          name: 'Em Andamento',
          funnel_id: funnel.id,
          position: 1,
          color: '#f59e0b',
          automation_type: nil
        )

        # Criar etapa "Resolvidos" com automação
        FunnelStage.create!(
          name: 'Resolvidos',
          funnel_id: funnel.id,
          position: 2,
          color: '#6b7280',
          automation_type: 'resolved'
        )

        funnel
      end
    rescue StandardError => e
      Rails.logger.error "Erro ao criar funil padrão para account #{@account.id}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      raise
    end
  end
end

