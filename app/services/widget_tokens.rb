# frozen_string_literal: true

# Tokens de marca do widget, calculados no SERVIDOR.
#
# Bloco 1.02 do PLANO-MESTRE (§2.2 · W1.2 = BE-7) · plano 22 §A.2.
#
# ── Por que no servidor, e não em JS dos dois lados ─────────────────────────
# O widget vive num iframe; o launcher vive no documento do site do cliente.
# São DOIS pontos de injeção. Duplicar a fórmula de contraste (uma em Ruby,
# outra em JS) é o caminho conhecido para o launcher e o header discordarem de
# novo — que é exatamente o defeito que esta onda conserta. O servidor calcula
# UMA vez e os dois lados consomem o resultado pronto.
#
# ── Por que no ERB, e não no `mounted()` ───────────────────────────────────
# `show.html.erb` escreve a configuração inline ANTES do `vite_javascript_tag`.
# Emitir os tokens ali elimina o flash de cor errada entre o 1º paint e o
# `App.vue` — hoje o widget pinta verde e depois corrige, e em conexão lenta
# isso é visível.
#
# ── A fórmula, e por que ela não é a que estava aqui ───────────────────────
# O que existia era `getContrastingTextColor` (YIQ, limiar 186) e
# `isWidgetColorLighter` (brilho ponderado 299/587/114, limiar 225). Nenhuma
# das duas é WCAG e nenhuma verifica se o resultado atinge razão alguma: elas
# divergem da regra WCAG em 11 de 16 cores de marca testadas [13 §3.2].
#
# Aqui a conta é a da WCAG 2.x:
#
#   luminância relativa  L = 0,2126·R + 0,7152·G + 0,0722·B, com cada canal
#                            linearizado (c/12,92 se c ≤ 0,04045, senão
#                            ((c+0,055)/1,055)^2,4)
#   razão de contraste   (L_claro + 0,05) / (L_escuro + 0,05)
#
# O limiar 0,17913 não é arbitrário: é a luminância em que contrastar com
# preto e contrastar com branco dão o MESMO número —
#   (L+0,05)/0,05 = 1,05/(L+0,05)  →  (L+0,05)² = 0,0525  →  L = 0,179129…
# Acima dele o preto ganha; abaixo, o branco. E é PRETO PURO (`#000000`), não
# o `#37546D` que o SDK usava: preto puro maximiza a razão e não introduz um
# matiz que briga com a marca.
#
# ── Segurança ──────────────────────────────────────────────────────────────
# `channel_web_widgets.widget_color` é `string` livre no banco. Emitir esse
# valor dentro de um `<style>` cria um vetor de injeção de CSS que hoje não
# existe. Por isso NADA que não case `#RRGGBB` (ou `#RGB`) chega à saída: a
# cor inválida é substituída pelo default e o texto do banco não é
# interpolado. Todos os outros tokens são DERIVADOS — saem de aritmética sobre
# três inteiros de 0 a 255, não de string.
class WidgetTokens
  DEFAULT_BRAND = '#1f93ff' # o mesmo default de `channel_web_widgets.widget_color`

  # Limiar WCAG de virada preto/branco. Ver dedução no cabeçalho.
  LUMINANCE_THRESHOLD = 0.17913

  # Alvo de contraste para a marca quando ela vira TEXTO (WCAG 1.4.3 AA).
  READABLE_TARGET = 4.5

  # As duas superfícies do widget. Em cada tema, a que importa é a de PIOR caso
  # para o texto — a mais clara no tema claro, a mais CLARA também no tema
  # escuro, porque é ela que aproxima a cor do fundo.
  #
  #   claro  → `--background-color: 253 253 253` ≈ #fdfdfd (uso #ffffff)
  #   escuro → o balão do agente, `--solid-3: 44 45 54` = #2c2d36
  #
  # ⚠️ `SURFACE_DARK` era `#121213`, o fundo do PAINEL, e estava errado — não
  # por gosto, por medição. `--w-brand-readable-dark` é o que pinta o LINK
  # dentro do balão do agente, e esse balão não é o painel: no escuro ele é
  # `bg-n-solid-3`, que é mais claro. Uma cor calibrada contra #121213 chega ao
  # balão abaixo do alvo. Medido em Chromium pelo check do bloco 2.03:
  #
  #   #009CE0 → 4,4486:1 sobre o balão (calibrado contra o painel)
  #   #1f93ff → 4,3470:1  — e este é o DEFAULT de `channel_web_widgets`,
  #                         ou seja, a inbox que ninguém configurou nascia
  #                         reprovando o aceite 2 da §C.5
  #
  # Calibrando contra o balão, os dois cruzam (4,6970 e 4,5801) e a marca que já
  # passava volta INTACTA — `#2dc46f` continua `#2dc46f`, com 6,0148:1. Trocar
  # para a superfície mais clara só pode aumentar contraste no tema escuro:
  # nenhum consumidor de `--w-brand-readable-dark` fica pior.
  SURFACE_LIGHT = '#ffffff'
  SURFACE_DARK = '#2c2d36'

  # Passo do ajuste de legibilidade e da variação de hover/press.
  READABLE_STEP = 0.05
  READABLE_MAX_STEPS = 20
  HOVER_MIX = 0.10
  ACTIVE_MIX = 0.18

  FULL_HEX = /\A#(\h{2})(\h{2})(\h{2})\z/
  SHORT_HEX = /\A#(\h)(\h)(\h)\z/

  attr_reader :brand

  def self.for(web_widget)
    new(web_widget.respond_to?(:widget_color) ? web_widget.widget_color : nil)
  end

  def initialize(widget_color)
    @brand = self.class.sanitize(widget_color)
  end

  # Só sai daqui `#rrggbb` minúsculo. Qualquer outra coisa vira o default —
  # é isto que impede a string do banco de atravessar para dentro do `<style>`.
  def self.sanitize(value)
    color = value.to_s.strip
    if (m = FULL_HEX.match(color))
      "##{m[1]}#{m[2]}#{m[3]}".downcase
    elsif (m = SHORT_HEX.match(color))
      "##{m[1] * 2}#{m[2] * 2}#{m[3] * 2}".downcase
    else
      DEFAULT_BRAND
    end
  end

  def self.rgb(hex)
    FULL_HEX.match(hex).captures.map { |c| c.to_i(16) }
  end

  def self.hex(rgb)
    red, green, blue = rgb.map { |c| c.round.clamp(0, 255) }
    format('#%<red>02x%<green>02x%<blue>02x', red: red, green: green, blue: blue)
  end

  def self.relative_luminance(hex)
    r, g, b = rgb(hex).map do |channel|
      s = channel / 255.0
      s <= 0.04045 ? s / 12.92 : (((s + 0.055) / 1.055)**2.4)
    end
    (0.2126 * r) + (0.7152 * g) + (0.0722 * b)
  end

  def self.contrast_ratio(color_a, color_b)
    lum_a = relative_luminance(color_a)
    lum_b = relative_luminance(color_b)
    lighter, darker = lum_a > lum_b ? [lum_a, lum_b] : [lum_b, lum_a]
    (lighter + 0.05) / (darker + 0.05)
  end

  def self.mix(color_a, color_b, amount)
    a = rgb(color_a)
    b = rgb(color_b)
    hex(a.each_with_index.map { |channel, i| channel + ((b[i] - channel) * amount) })
  end

  # Preto puro ou branco puro — o que der a maior razão contra a cor de fundo.
  def self.on_color(hex)
    relative_luminance(hex) > LUMINANCE_THRESHOLD ? '#000000' : '#ffffff'
  end

  # A marca como TEXTO sobre uma superfície: escurece (ou clareia) em passos de
  # 5% até cruzar 4,5:1. Se já cruza, volta intacta — a marca do cliente só é
  # alterada quando ela seria ilegível.
  def self.readable_on(brand, surface, target = READABLE_TARGET)
    color = brand
    direction = on_color(surface)
    READABLE_MAX_STEPS.times do
      break if contrast_ratio(color, surface) >= target

      color = mix(color, direction, READABLE_STEP)
    end
    color
  end

  def on_brand
    @on_brand ||= self.class.on_color(brand)
  end

  def brand_hover
    @brand_hover ||= self.class.mix(brand, on_brand, HOVER_MIX)
  end

  def brand_active
    @brand_active ||= self.class.mix(brand, on_brand, ACTIVE_MIX)
  end

  def brand_readable
    @brand_readable ||= self.class.readable_on(brand, SURFACE_LIGHT)
  end

  def brand_readable_dark
    @brand_readable_dark ||= self.class.readable_on(brand, SURFACE_DARK)
  end

  def contrast_on_brand
    self.class.contrast_ratio(brand, on_brand)
  end

  # Os tokens do `:root`. Chaves = nomes das custom properties de `_tokens.scss`.
  def root_tokens
    {
      '--w-brand' => brand,
      '--w-brand-hover' => brand_hover,
      '--w-brand-active' => brand_active,
      '--w-on-brand' => on_brand,
      '--w-brand-readable' => brand_readable,
      '--w-brand-readable-dark' => brand_readable_dark,
      '--w-focus-ring-color' => brand_readable
    }
  end

  # Os tokens que o tema escuro sobrescreve.
  #
  # ⚠️ Isto NÃO é detalhe cosmético. `_tokens.scss` declara os fallbacks dentro
  # de `@layer base`, e no cascade **regra sem camada vence regra em camada**,
  # independentemente da especificidade. Se o servidor emitisse só o `:root`
  # sem camada, ele venceria o `.dark { … }` de `_tokens.scss` e o widget
  # ficaria com a variante clara no tema escuro. Os dois seletores têm de sair
  # do mesmo `<style>`.
  def dark_tokens
    {
      '--w-brand-readable' => 'var(--w-brand-readable-dark)',
      '--w-focus-ring-color' => 'var(--w-brand-readable-dark)'
    }
  end

  def css
    "#{declaration_block(':root', root_tokens)}#{declaration_block('.dark', dark_tokens)}"
  end

  # O payload que atravessa a ponte para o launcher (bloco 1.03). Mesma fonte,
  # mesmos valores — o host não recalcula nada.
  def to_h
    root_tokens
  end

  private

  def declaration_block(selector, tokens)
    "#{selector}{#{tokens.map { |name, value| "#{name}:#{value}" }.join(';')}}"
  end
end
