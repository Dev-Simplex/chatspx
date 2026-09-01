module Campaigns
  module Whatsapp
    # A gramatica de telefone brasileiro das listas de disparo — sem banco, sem
    # campanha, so string entra e string sai.
    #
    # CHAVE CANONICA = DDD + ultimos 8 digitos. E o que colapsa as variantes do 9o
    # digito e do DDI: `+5566992927211`, `+556692927211` e `66 9929-2721` sao a
    # MESMA pessoa. Deduplicar pela string e164 deixaria os tres passarem como tres
    # destinatarios e o lead levaria o disparo em triplicata.
    #
    # Vive separado do AudienceBuilderService porque sao dois trabalhos: aqui e
    # "que numero e esse"; la e "esse numero entra no disparo". O `default_ddd` e a
    # unica coisa que a campanha precisa dizer pra ca.
    class CanonicalPhone
      DDDS = %w[
        11 12 13 14 15 16 17 18 19 21 22 24 27 28 31 32 33 34 35 37 38
        41 42 43 44 45 46 47 48 49 51 53 54 55 61 62 63 64 65 66 67 68
        69 71 73 74 75 77 79 81 82 83 84 85 86 87 88 89 91 92 93 94 95
        96 97 98 99
      ].freeze

      # Assinante de 8 digitos comecando em 2-5 e telefone FIXO: nao recebe
      # WhatsApp, e acrescentar o 9o digito produz um celular que nao existe.
      LANDLINE_PREFIXES = %w[2 3 4 5].freeze

      # Mesmo digito 7+ vezes seguidas ("66999999999"): preenchimento de formulario
      # pra escapar de campo obrigatorio, nunca um numero real.
      SUSPICIOUS = /(\d)\1{6,}/

      def initialize(default_ddd: nil)
        @default_ddd = default_ddd.to_s.gsub(/\D/, '')
      end

      # Devolve [ddd, assinante] do numero brasileiro, ou nil quando irrecuperavel.
      def split_number(raw)
        digits = recover(raw.to_s.gsub(/\D/, ''))
        return nil unless digits.length.between?(10, 11)

        ddd = digits[0, 2]
        DDDS.include?(ddd) ? [ddd, digits[2..]] : nil
      end

      def landline?(subscriber)
        subscriber.length == 8 && LANDLINE_PREFIXES.include?(subscriber[0])
      end

      def suspicious?(ddd, subscriber)
        "#{ddd}#{subscriber}".match?(SUSPICIOUS)
      end

      def canonical(ddd, subscriber)
        "#{ddd}#{subscriber[-8..]}"
      end

      def canonical_of(raw)
        ddd, subscriber = split_number(raw)
        ddd && canonical(ddd, subscriber)
      end

      # Assinante de 8 digitos e celular legado: ganha o 9o digito. Sem isso a
      # maioria das listas (que chegam em 8 digitos) falha como inexistente.
      def e164(ddd, subscriber)
        subscriber = "9#{subscriber}" if subscriber.length == 8
        "+55#{ddd}#{subscriber}"
      end

      # As DUAS formas e164 da mesma chave (com e sem o 9o digito) — a ficha do
      # contato pode ter nascido em qualquer uma.
      def e164_variants(canonical)
        ddd = canonical[0, 2]
        subscriber = canonical[2..]
        ["+55#{ddd}#{subscriber}", "+55#{ddd}9#{subscriber}"]
      end

      private

      attr_reader :default_ddd

      # As tres formas erradas que as listas reais trazem (ver ingestao_*.py), na
      # ordem em que precisam ser desfeitas.
      def recover(digits)
        prefix_default_ddd(strip_country_code(strip_trunk_zero(digits)))
      end

      # Zero de tronco da discagem nacional: "066 9929-2721".
      def strip_trunk_zero(digits)
        digits.start_with?('0') && digits.length.between?(11, 12) ? digits[1..] : digits
      end

      # DDI colado no numero: "5566992927211".
      def strip_country_code(digits)
        digits.start_with?('55') && digits.length >= 12 ? digits[2..] : digits
      end

      # Numero sem DDD ("99292721"): so da pra recuperar quando a campanha declara
      # a regiao — sem isso nao ha como adivinhar de onde e o numero.
      def prefix_default_ddd(digits)
        return digits if default_ddd.blank? || !digits.length.between?(8, 9)

        "#{default_ddd}#{digits}"
      end
    end
  end
end
