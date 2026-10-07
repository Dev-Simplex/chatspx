# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CampaignRecipient do
  def recipient(status, external_error = nil)
    described_class.new(status: status, external_error: external_error)
  end

  describe '#reason_code' do
    it 'extrai o código da Meta da falha' do
      expect(recipient(:failed, '131026: Message undeliverable').reason_code).to eq('131026')
    end

    it 'marca falha sem código como erro de envio' do
      expect(recipient(:failed, 'StandardError: boom').reason_code).to eq('erro_envio')
    end

    it 'devolve o código de bloqueio gravado pelo motor' do
      expect(recipient(:skipped, 'atendimento_ativo').reason_code).to eq('atendimento_ativo')
    end

    it 'reconhece as frases gravadas antes dos códigos' do
      expect(recipient(:skipped, 'contato em atendimento ativo').reason_code).to eq('atendimento_ativo')
      expect(recipient(:skipped, 'caixa somente leitura').reason_code).to eq('caixa_somente_leitura')
    end

    it 'trata cancelado sem motivo como cancelado' do
      expect(recipient(:cancelled).reason_code).to eq('cancelado')
    end
  end

  describe '#reason_label' do
    it 'traduz o código conhecido da Meta' do
      label = I18n.with_locale(:pt_BR) { recipient(:failed, '131047: Re-engagement message').reason_label }

      expect(label).to eq('Fora da janela de 24h: só template pode ser enviado')
    end

    it 'agrupa código de template fora do catálogo' do
      label = I18n.with_locale(:pt_BR) { recipient(:failed, '132999: Template whatever').reason_label }

      expect(label).to start_with('Problema no template')
    end

    it 'mostra o texto cru da Meta quando o código é desconhecido' do
      expect(recipient(:failed, '999999: Something new').reason_label).to eq('999999: Something new')
    end
  end
end
