# frozen_string_literal: true

# Recebe relatórios de erro do widget — bloco 2.13.
#
# NÃO herda de `Api::V1::Widget::BaseController` de propósito. Aquele controller
# roda `set_contact`, que exige um `contact_inbox` já criado e levanta
# `RecordNotFound` quando não há. Mas boa parte dos erros que queremos ver
# acontece ANTES de existir contato — inclusive erros NA criação dele. Herdar
# dali faria a telemetria falhar exatamente nos casos mais interessantes.
#
# O que se valida é só o `website_token`: ele diz de qual conta é o relatório, e
# é público por natureza (está no snippet de todo site).
class Api::V1::Widget::TelemetryController < ApplicationController
  include WebsiteTokenHelper

  before_action :set_web_widget

  def create
    Widget::ErrorReport.new(report_params, @web_widget).perform

    # `no_content` sempre, mesmo quando o Sentry não está configurado. O widget
    # não tem o que fazer com uma falha daqui, e devolver erro só o levaria a
    # tentar de novo — telemetria não pode virar tráfego de retentativa no site
    # do cliente.
    head :no_content
  end

  private

  def report_params
    # Lista FECHADA, espelhando `CHAVES_DO_ENVELOPE` de
    # `widget/helpers/telemetry.js`. Sem `permit!` e sem "resto": é o que
    # impede um cliente adulterado de despejar a conversa do visitante aqui
    # dentro. Chave fora da lista é DESCARTADA, não rejeitada — rejeitar faria
    # o widget tentar de novo.
    params.permit(:name, :message, :stack, :url, :release, :website_token, context: [:origem])
          .to_h
          .with_indifferent_access
  end

  def permitted_params
    params.permit(:website_token)
  end
end
