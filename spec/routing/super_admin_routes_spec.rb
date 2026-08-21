require 'rails_helper'

# TRAVA. O painel super_admin monta a barra lateral percorrendo TODOS os recursos do namespace
# (`Administrate::Namespace.new(namespace).resources` em
# `app/views/super_admin/application/_navigation.html.erb`) e gerando um link de `index` para
# cada um. A barra vive no LAYOUT, entao um unico recurso sem controller derruba TODAS as
# paginas do painel com 500 — nao so a dele.
#
# Foi o que aconteceu: `push_diagnostics` e `platform_banners` entraram nas rotas sem controller
# e o super_admin inteiro parou. Nenhum spec apontava a causa, porque cada spec de super_admin
# olha so a propria pagina — os 13 falhavam juntos, todos com o mesmo 500 mudo.
#
# Este exemplo transforma esse 500 em teste vermelho no lugar certo.
RSpec.describe 'rotas do super_admin', type: :routing do
  it 'toda rota do namespace super_admin tem um controller que existe' do
    orfas = Rails.application.routes.routes.filter_map do |rota|
      controller = rota.defaults[:controller]
      next if controller.blank? || !controller.start_with?('super_admin/')

      begin
        Object.const_get("#{controller.camelize}Controller")
        nil
      rescue NameError
        controller
      end
    end.uniq

    expect(orfas).to eq([])
  end

  # Anti-vacuo: se o filtro parasse de casar (renomeacao do namespace, por exemplo), o exemplo
  # acima passaria examinando ZERO rotas e nao provaria nada.
  it 'nao passa no vacuo: existem rotas de super_admin para examinar' do
    total = Rails.application.routes.routes.count { |r| r.defaults[:controller].to_s.start_with?('super_admin/') }
    expect(total).to be > 20
  end
end
