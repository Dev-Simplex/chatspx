require 'rails_helper'

describe '/widget_tests', type: :request do
  before do
    create(:channel_widget)
  end

  describe 'GET /widget_tests' do
    it 'renders the page correctly' do
      get widget_tests_url
      expect(response).to be_successful
    end

    # Bloco 2.10. Esta página é a que a equipe usa para conferir o widget, então
    # o default dela precisa ser o MESMO do produto (`DEFAULT_DARK_MODE` em
    # `sdk/constants.js`). Enquanto era `light`, a ferramenta de conferência
    # mostrava um comportamento que nenhum cliente novo tem.
    it 'usa o mesmo default de tema do produto quando nada é pedido' do
      get widget_tests_url

      expect(response.body).to include("darkMode: 'auto'")
    end

    it 'ainda permite forçar um tema pela URL' do
      get widget_tests_url(dark_mode: 'dark')

      expect(response.body).to include("darkMode: 'dark'")
    end
  end
end
