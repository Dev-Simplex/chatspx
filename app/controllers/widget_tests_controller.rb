class WidgetTestsController < ActionController::Base
  before_action :ensure_web_widget
  before_action :ensure_widget_position
  before_action :ensure_widget_type
  before_action :ensure_widget_style
  before_action :ensure_dark_mode

  def index
    render
  end

  private

  def ensure_widget_style
    @widget_style = params[:widget_style] || 'standard'
  end

  # Bloco 2.10. Esta página de teste é a que a equipe usa para conferir o
  # widget, então o default dela precisa ser o MESMO do produto — senão a
  # ferramenta de conferência passa a mostrar um comportamento que nenhum
  # cliente tem. O default do produto é `auto` (ver `sdk/constants.js`,
  # `DEFAULT_DARK_MODE`). O override por `?dark_mode=` continua valendo.
  def ensure_dark_mode
    @dark_mode = params[:dark_mode] || 'auto'
  end

  def ensure_widget_position
    @widget_position = params[:position] || 'left'
  end

  def ensure_widget_type
    @widget_type = params[:type] || 'expanded_bubble'
  end

  def inbox_id
    @inbox_id ||= params[:inbox_id] || Channel::WebWidget.first.inbox.id
  end

  def ensure_web_widget
    @inbox = Inbox.find(inbox_id)
    @web_widget = @inbox.channel
  end
end
