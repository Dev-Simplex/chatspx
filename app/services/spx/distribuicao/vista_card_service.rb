# Espelha a designação no Vista/Loft: garante o cliente e abre o card do negócio com o
# corretor escolhido pelo rodízio (SPEC-RODIZIO §8).
#
# É ASSIM que o corretor de vendas fica sabendo do lead — ele não vive no SPX, vive no Vista.
# Direção ÚNICA: SPX → Vista. A máquina de estados NÃO depende do retorno daqui; falhar aqui
# não desfaz a designação, que já está gravada no log.
#
# ⚠️ NÃO EXISTE DESFAZER — o DELETE do Vista responde 401. Consequências no desenho:
#   - idempotente em DOIS níveis: carimbo local (`vista_negocio_codigo`) + negócio ativo do
#     cliente no Vista;
#   - RECUSA criar quando falta qualquer dado obrigatório. Card no corretor errado é pior
#     que card ausente, porque ninguém consegue apagar depois.
#
# ⚠️ CONTRATO EMPÍRICO: o Vista não publica catálogo de campos. Os nomes abaixo vieram do
# teste ao vivo de 23/07 (STATE.md). O contrato só fecha de verdade contra um card criado
# por este serviço — validar antes de ligar `espelho_vista` em produção.
module Spx
  module Distribuicao
    class VistaCardService
      CARIMBO = 'vista_negocio_codigo'.freeze

      def initialize(conversation:, policy:, user_id:, produto_slug: nil)
        @conversation = conversation
        @policy = policy
        @user_id = user_id
        @produto_slug = produto_slug
      end

      def perform
        return unless @policy.espelho_vista?
        return if ja_espelhado?
        return pular('sem credencial vista') if chave.blank?

        corretor = vista_corretor
        return pular('pool sem vista_corretor') if corretor.blank?

        cfg = config_do_card
        return pular('sem pipe/etapa configurados') if cfg['pipe'].blank? || cfg['etapa'].blank?

        codigo_cliente = garantir_cliente(cfg)
        return pular('cliente nao resolvido') if codigo_cliente.blank?
        return pular("cliente #{codigo_cliente} ja tem negocio ativo") if negocio_ativo?(codigo_cliente)

        gravar!(criar_negocio(codigo_cliente, corretor, cfg))
      rescue StandardError => e
        Rails.logger.error("[Distribuicao] vista conv=#{@conversation&.id}: #{e.class}: #{e.message}")
      end

      private

      def pular(motivo)
        Rails.logger.info("[Distribuicao] vista conv=#{@conversation.id} — nao criou card: #{motivo}")
        nil
      end

      def ja_espelhado?
        (@conversation.custom_attributes || {})[CARIMBO].present?
      end

      # ---------------------------------------------------------------- config

      # Mesma ordem de prioridade do Captain::Tools::IntegrationCredentials (que não dá pra
      # incluir aqui: ele depende de @assistant, e este serviço parte da conversa).
      def chave
        return @chave if defined?(@chave)

        conta = @conversation.account
        @chave = (AccountIntegration.settings_for(conta, 'vista') || {})['vista_api_key'].presence ||
                 (conta.custom_attributes || {})['vista_api_key'].presence ||
                 ENV['TOZI_VISTA_API_KEY'].presence
      end

      def base_url
        conta = @conversation.account
        (AccountIntegration.settings_for(conta, 'vista') || {})['vista_base_url'].presence ||
          (conta.custom_attributes || {})['vista_base_url'].presence ||
          ENV.fetch('TOZI_VISTA_BASE_URL', 'https://toz19328-rest.vistahost.com.br')
      end

      # Produto tem precedência; a policy cobre o lead sem produto identificado.
      def config_do_card
        (@policy.vista_padrao || {}).merge(produto_vista)
      end

      def produto_vista
        return {} if @produto_slug.blank?

        Produto.ativos.find_by(account_id: @conversation.account_id, slug: @produto_slug)&.vista.presence || {}
      end

      # O identificador do corretor NO VISTA — não é o user_id do SPX. Vem explícito na
      # entrada do pool: sem mapeamento declarado, não se chuta (ver "não existe desfazer").
      def vista_corretor
        entrada = (@policy.pool || []).find { |e| e['user_id'].to_i == @user_id.to_i }
        entrada && entrada['vista_corretor'].presence
      end

      # ---------------------------------------------------------------- cliente

      # O Vista DEDUPA POR TELEFONE sozinho: reenviar o mesmo celular devolve o cliente que
      # já existe em vez de duplicar. Por isso "garantir" e não "criar".
      def garantir_cliente(cfg)
        contato = @conversation.contact
        return nil if contato.nil? || telefone(contato).blank?

        campos = {
          'Nome' => nome_do_contato(contato),
          'Celular' => telefone(contato),
          'FonePrincipal' => telefone(contato),
          'VeiculoCaptacao' => cfg['veiculo_captacao'],
          'Interesse' => cfg['interesse']
        }.compact
        resposta = post_json('/clientes/detalhes', { 'fields' => campos })
        extrair_codigo(resposta, %w[Codigo CodigoCliente])
      end

      def nome_do_contato(contato)
        (contato.custom_attributes || {})['nome_confirmado'].presence || contato.name.presence
      end

      def telefone(contato)
        contato.phone_number.to_s.delete('+').strip.presence
      end

      # ---------------------------------------------------------------- negócio

      # Segunda trava de idempotência: o cliente pode já estar sendo trabalhado num negócio
      # aberto (inclusive criado à mão pela recepção). Nesse caso NÃO abrimos outro.
      def negocio_ativo?(codigo_cliente)
        resposta = get_json('/negocios/listar',
                            pesquisa: { fields: %w[Codigo CodigoCliente Situacao], filter: { 'CodigoCliente' => codigo_cliente } },
                            codigo_cliente: codigo_cliente)
        return false unless resposta.is_a?(Hash)

        resposta.values.any? { |v| v.is_a?(Hash) && v['Codigo'].present? }
      end

      # O payload do negócio vai no parâmetro `cadastro` como STRING JSON — diferente do
      # cliente, que aceita body JSON. Assimetria do Vista, confirmada no teste ao vivo.
      def criar_negocio(codigo_cliente, corretor, cfg)
        campos = {
          'NomeNegocio' => nome_do_negocio(cfg),
          'VeiculoCaptacao' => cfg['veiculo_captacao'],
          'CodigoCliente' => codigo_cliente,
          'CorretorNegocio' => corretor,
          'CodigoPipe' => cfg['pipe'],
          'EtapaAtual' => cfg['etapa']
        }.compact
        resposta = post_form('/negocios/detalhes', cadastro: { 'fields' => campos }.to_json)
        extrair_codigo(resposta, %w[Codigo CodigoNegocio])
      end

      def nome_do_negocio(cfg)
        titulo = (@conversation.custom_attributes || {})['meta_imovel'].presence ||
                 @produto_slug.presence ||
                 @conversation.contact&.name
        "#{cfg['prefixo_nome_negocio']}#{titulo}".strip
      end

      # ---------------------------------------------------------------- saída

      # Grava nos dois lugares: na conversa (idempotência + visibilidade) e na designação
      # aberta (é o log que a tela lê).
      def gravar!(codigo)
        return pular('vista nao devolveu codigo do negocio') if codigo.blank?

        @conversation.update!(custom_attributes: (@conversation.custom_attributes || {}).merge(CARIMBO => codigo))
        Log.designacao_aberta(@conversation.id)&.update!(vista_negocio_codigo: codigo)
        codigo
      end

      # ---------------------------------------------------------------- http

      def post_json(path, body)
        resposta = HTTParty.post("#{base_url}#{path}",
                                 query: { key: chave },
                                 body: body.to_json,
                                 headers: { 'Accept' => 'application/json', 'Content-Type' => 'application/json' })
        resposta.success? ? resposta.parsed_response : registrar_falha(path, resposta)
      end

      def post_form(path, params)
        resposta = HTTParty.post("#{base_url}#{path}",
                                 query: { key: chave }.merge(params),
                                 headers: { 'Accept' => 'application/json' })
        resposta.success? ? resposta.parsed_response : registrar_falha(path, resposta)
      end

      def get_json(path, params)
        params = params.transform_values { |v| v.is_a?(Hash) ? v.to_json : v }
        resposta = HTTParty.get("#{base_url}#{path}",
                                query: { key: chave }.merge(params),
                                headers: { 'Accept' => 'application/json' })
        resposta.success? ? resposta.parsed_response : registrar_falha(path, resposta)
      end

      def registrar_falha(path, resposta)
        Rails.logger.warn("[Distribuicao] vista #{path} conv=#{@conversation.id} http=#{resposta&.code}")
        nil
      end

      # O Vista devolve ora o registro na raiz, ora aninhado por código. Aceita as duas formas.
      def extrair_codigo(resposta, chaves)
        return nil unless resposta.is_a?(Hash)

        direto = chaves.filter_map { |k| resposta[k].presence }.first
        return direto.to_s if direto.present?

        aninhado = resposta.values.find { |v| v.is_a?(Hash) && chaves.any? { |k| v[k].present? } }
        aninhado && chaves.filter_map { |k| aninhado[k].presence }.first.to_s
      end
    end
  end
end
