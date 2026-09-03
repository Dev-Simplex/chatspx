# frozen_string_literal: true

# Mecanismo de aceite do bloco 1.06 — a parte do `lang` no documento.
#
# Roda SEM Rails e SEM banco, como o spec do 1.02: o que se verifica é a linha
# `<html>` do ERB e o valor que ela produz. `.rspec` já carrega `spec_helper`.
#
# Este spec não se contenta em grepar o atributo: ele AVALIA a linha do ERB com
# um duplo de `@web_widget`, porque o defeito interessante não é a ausência do
# atributo — é ele sair com o valor errado. O locale interno usa `_` (`pt_BR`) e
# o BCP 47 exige `-` (`pt-BR`); um `lang="pt_BR"` é tão inútil para o leitor de
# tela quanto nenhum, e passaria por qualquer grep de `lang=`.
require 'erb'

RSpec.describe 'widgets/show.html.erb — lang do documento' do
  let(:caminho) do
    File.expand_path('../../../app/views/widgets/show.html.erb', __dir__)
  end
  let(:linhas) { File.read(caminho).lines }
  let(:linha_html) { linhas.find { |l| l.lstrip.start_with?('<html') } }

  describe 'a tag existe e é a raiz do documento' do
    it 'declara lang na tag <html>' do
      expect(linha_html).not_to be_nil, 'show.html.erb não tem tag <html>'
      expect(linha_html).to include('lang=')
    end
  end

  describe 'o valor sai do locale da conta, em BCP 47' do
    it 'converte pt_BR para pt-BR' do
      conta = Struct.new(:locale).new('pt_BR')
      widget = Struct.new(:account).new(conta)
      resultado = renderizar(linha_html, widget)

      expect(resultado).to include('lang="pt-BR"')
      # A asserção que pega o erro de verdade: o underscore não pode sobreviver.
      expect(resultado).not_to include('pt_BR')
    end

    it 'deixa locale de uma só parte intacto' do
      conta = Struct.new(:locale).new('en')
      widget = Struct.new(:account).new(conta)

      expect(renderizar(linha_html, widget)).to include('lang="en"')
    end

    it 'funciona com locale que chega como símbolo' do
      # `account.locale` é enum; dependendo do caminho ele chega como símbolo.
      conta = Struct.new(:locale).new(:pt_BR)
      widget = Struct.new(:account).new(conta)

      expect(renderizar(linha_html, widget)).to include('lang="pt-BR"')
    end
  end

  def renderizar(linha, web_widget)
    contexto = Object.new
    contexto.instance_variable_set(:@web_widget, web_widget)
    contexto.instance_eval do
      def render_linha(linha)
        ERB.new(linha).result(binding)
      end
    end
    contexto.render_linha(linha)
  end
end
