# Como a produção apresenta uma mensagem do banco AO MODELO.
#
# Mensagem do banco não é turno do modelo. Entre uma e outra o
# Captain::Conversation::ResponseBuilderJob decide TRÊS coisas, e todas mudam o cenário:
#
#   1. se entra  — #survey_message? descarta NPS/CSAT;
#   2. com que papel — #determine_role: incoming vira 'user', o resto vira 'assistant';
#   3. com que texto — #outgoing_content troca payload interativo e anexo por um rótulo.
#
# Sem registrar isso, a fixture afirmaria coisas sobre texto que o modelo nunca viu. O carrossel
# da conv 41803 é o exemplo: o banco guarda "📷 Carrossel: 9 fotos do imóvel 9412", que é rótulo
# de PAINEL, e o modelo recebe "[carrossel de fotos do imóvel 9412 enviado]".
#
# Espelho, não reimplementação: se a produção mudar, isto fica errado em silêncio. É o preço de
# gravar a partir de um JSON exportado em vez de rodar o job — e é por isso que cada regra aqui
# aponta o método de lá pelo nome.
class Spx::Harness::Apresentacao
  ROTULO_INTERATIVO = 'mensagem interativa enviada'.freeze
  ROTULO_ANEXO = 'foto do imóvel enviada'.freeze

  class << self
    # 'omitido' | 'user' | 'assistant' — o papel com que a mensagem chega ao modelo.
    #
    # O `meta_lead_ads_initial` cai em 'assistant' e isso NÃO é engano do gravador: nada o
    # filtra, e o template da campanha entra no contexto como fala do próprio agente. Ver a
    # dívida nomeada no §15 do doc 06.
    def papel(mensagem)
      return 'omitido' if mensagem['marcador'].to_s == 'nps_survey'

      mensagem['direcao'].to_s == 'incoming' ? 'user' : 'assistant'
    end

    # Espelha ResponseBuilderJob#outgoing_content. Só o lado de SAÍDA: o de entrada passa por
    # multimodal e contexto de citação, que dependem de anexo e de mensagem citada — dado que a
    # exportação não carrega. Mensagem de entrada fica com o texto do banco, e a fixture não
    # afirma nada sobre o que o modelo viu além disso.
    def texto(mensagem)
      return mensagem['texto'].to_s if mensagem['direcao'].to_s == 'incoming'
      return "[#{rotulo(mensagem, ROTULO_INTERATIVO, 'carrossel de fotos do imóvel %<codigo>s enviado')}]" if
        mensagem['interativo']
      return mensagem['texto'].to_s if mensagem['texto'].to_s.present?
      return '' unless mensagem['anexos'].to_i.positive?

      "[#{rotulo(mensagem, ROTULO_ANEXO, 'foto do imóvel %<codigo>s enviada')}]"
    end

    # Fala GERADA pelo agente — a única coisa que pode carregar afirmação dele.
    #
    # Fica de fora o que chega ao modelo como turno do assistente sem ser fala: rótulo de
    # payload interativo, placeholder de anexo e template de campanha. Cobrar do agente um preço
    # escrito pela campanha, ou um código escrito pelo próprio sistema ao registrar um envio
    # confirmado, acusaria invenção onde não houve nenhuma.
    def fala_do_agente?(mensagem)
      mensagem['de'].to_s == 'ia' &&
        mensagem['marcador'].blank? &&
        !mensagem['interativo'] &&
        mensagem['anexos'].to_i.zero? &&
        mensagem['texto'].to_s.present?
    end

    private

    def rotulo(mensagem, generico, com_codigo)
      codigo = mensagem['property_code'].to_s
      codigo.present? ? format(com_codigo, codigo: codigo) : generico
    end
  end
end
