# frozen_string_literal: true

require 'rails_helper'

# Mecanismo do aceite do bloco 0.8, item 2 (D11): "inbox criada por tela e por
# API nasce com a MESMA cor".
#
# Este arquivo cobre o lado Ruby — o caminho da API e o do onboarding. O lado da
# tela e coberto por
# `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/specs/Website.defaultColor.spec.js`,
# e a igualdade entre os dois valores por
# `app/javascript/dashboard/constants/specs/widgetColorDefault.spec.js`.
RSpec.describe Channel::WebWidget do
  describe 'default de cor do widget (D11)' do
    let(:account) { create(:account) }

    it 'nasce com o verde da marca ChatSPX quando ninguem informa cor' do
      # Este e o caminho da API: POST /api/v1/accounts/:id/inboxes sem
      # `widget_color` no payload. Antes caia no default da coluna (#1f93ff) e a
      # inbox nascia azul, enquanto a tela nascia verde.
      channel = described_class.new(account: account, website_url: 'https://exemplo.com.br')

      expect(channel.widget_color).to eq('#2dc46f')
    end

    it 'persiste o verde da marca quando a cor nao e informada' do
      channel = described_class.create!(account: account, website_url: 'https://exemplo.com.br')

      expect(channel.reload.widget_color).to eq('#2dc46f')
    end

    it 'nao sobrescreve a cor que o cliente escolheu' do
      # A tela manda `widget_color` explicito. O default nao pode passar por cima
      # — inclusive porque e assim que o cliente troca a cor para a marca dele.
      channel = described_class.create!(
        account: account, website_url: 'https://exemplo.com.br', widget_color: '#ff00aa'
      )

      expect(channel.reload.widget_color).to eq('#ff00aa')
    end

    it 'o onboarding usa exatamente o mesmo default, nao um proprio' do
      # Terceiro caminho de criacao, que o plano nao tinha registrado: cravava
      # '#1f93ff' numa constante propria.
      expect(Onboarding::WebWidgetCreationService::DEFAULT_WIDGET_COLOR).to eq(described_class::DEFAULT_WIDGET_COLOR)
    end

    it 'nao repinta inbox que ja existe' do
      # Trava dura do coordenador: mudar o default nao pode mexer em widget de
      # cliente que ja esta no ar. Simula o registro antigo gravando direto na
      # coluna, sem passar pelo default do model.
      legacy = described_class.create!(
        account: account, website_url: 'https://legado.com.br', widget_color: '#1f93ff'
      )

      legacy.update!(welcome_title: 'titulo novo')

      expect(legacy.reload.widget_color).to eq('#1f93ff')
    end
  end
end
