class Api::V1::Widget::EventsController < Api::V1::Widget::BaseController
  include Events::Types

  # O nome do evento vinha do site do cliente e ia direto para o barramento:
  # qualquer string virava um publish para TODOS os listeners registrados, e o
  # EventDispatcherJob (fila `critical`, retry_on attempts: 3) ainda gastava 3
  # tentativas com cada nome que fizesse um listener explodir.
  #
  # O widget so emite dois nomes por este endpoint:
  #   webwidget.triggered  — sdk/IFrameHelper.js:253
  #   campaign.triggered   — widget/api/endPoints.js:105
  PERMITTED_EVENT_NAMES = [WEBWIDGET_TRIGGERED, CAMPAIGN_TRIGGERED].freeze

  def create
    unless PERMITTED_EVENT_NAMES.include?(permitted_params[:name])
      render json: { error: "name must be one of: #{PERMITTED_EVENT_NAMES.join(', ')}" },
             status: :unprocessable_entity and return
    end

    Rails.configuration.dispatcher.dispatch(permitted_params[:name], Time.zone.now, contact_inbox: @contact_inbox,
                                                                                    event_info: permitted_params[:event_info].to_h.merge(event_info))
    head :no_content
  end

  private

  def event_info
    {
      widget_language: params[:locale],
      browser_language: browser.accept_language.first&.code,
      browser: browser_params
    }
  end

  def permitted_params
    params.permit(:name, :website_token, event_info: {})
  end
end
