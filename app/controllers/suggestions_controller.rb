# SUG-02: pagina publica /sugestoes (sem login). So devolve a casca HTML; o envio vai para
# Public::Api::V1::SuggestionsController. Nenhum dado de conta ou usuario passa por aqui.
class SuggestionsController < ActionController::Base
  before_action :set_global_config

  def new; end

  private

  def set_global_config
    @global_config = GlobalConfig.get('LOGO_THUMBNAIL', 'LOGO', 'LOGO_DARK', 'INSTALLATION_NAME')
  end
end
