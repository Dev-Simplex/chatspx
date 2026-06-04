# Manual de Marca — SPX (spec canônica)

> **Especificação de marca da SPX / Simplex Soluções**, autocontida e legível por humanos e por IA.
> Entregue esta URL a um dev ou a um assistente de IA e ele tem **tudo** para aplicar a identidade
> visual SPX em qualquer projeto (web app, landing, painel, e-mail, material gráfico).
>
> **URL canônica deste documento:** `https://chat.simplexsolucoes.com.br/brand/manual-marca-spx.md`
> **Os links de logo abaixo são absolutos e estão no ar** — podem ser baixados/referenciados direto.

---

## 0. Referência rápida (machine-readable)

```yaml
brand:
  name: "SPX"
  owner: "Simplex Soluções"
  primary_color: "#2dc46f"          # verde — light
  primary_color_dark: "#25d366"     # verde — dark
  primary_hover: "#008c70"          # light
  primary_hover_dark: "#4de598"     # dark
  on_primary: "#ffffff"             # texto/ícone sobre o verde
  fonts:
    ui: "Inter"                     # variável 100–900
    display: "InterDisplay"         # variável 100–900
  dark_mode: "class (.dark no root)"

assets_base: "https://chat.simplexsolucoes.com.br"

logos:
  horizontal_light: "https://chat.simplexsolucoes.com.br/brand-assets/logo.svg"          # símbolo + wordmark, fundo claro
  horizontal_dark:  "https://chat.simplexsolucoes.com.br/brand-assets/logo_dark.svg"     # símbolo + wordmark, fundo escuro
  symbol_light:     "https://chat.simplexsolucoes.com.br/brand-assets/logo_thumbnail.svg"      # só símbolo, fundo claro
  symbol_white:     "https://chat.simplexsolucoes.com.br/brand-assets/logo_thumbnail-branca.svg" # só símbolo branco, fundo escuro/colorido
  symbol_vector:    "https://chat.simplexsolucoes.com.br/brand-assets/logo_thumbnail2.svg"      # vetor verde limpo (favicon/app icon)

favicons:
  svg:        "https://chat.simplexsolucoes.com.br/brand-assets/logo_thumbnail.svg"
  png_16:     "https://chat.simplexsolucoes.com.br/favicon-16x16.png"
  png_32:     "https://chat.simplexsolucoes.com.br/favicon-32x32.png"
  png_96:     "https://chat.simplexsolucoes.com.br/favicon-96x96.png"
  png_512:    "https://chat.simplexsolucoes.com.br/favicon-512x512.png"
  apple_180:  "https://chat.simplexsolucoes.com.br/apple-icon.png"
  android_192:"https://chat.simplexsolucoes.com.br/android-icon-192x192.png"
  manifest:   "https://chat.simplexsolucoes.com.br/manifest.json"

semantic_colors:        # light / dark
  success: ["#2dc46f", "#25d366"]
  warning: ["#ffc53d", "#ffc53d"]
  error:   ["#e54666", "#e54666"]
  info:    ["#2dc46f", "#53bdeb"]
```

> ⚠️ **Não use** o conjunto de logos **azul legado** (`logo1.svg`, `logo2.svg`, `logo_dark1.svg`, `logo_dark2.svg`, `logo_thumbnail1.svg`) — é herança CorelDRAW/Chatwoot, não é a identidade verde SPX.

---

## 1. Essência

| | |
|---|---|
| **Marca** | SPX (Simplex Soluções) |
| **Cor primária** | **Verde `#2dc46f`** |
| **Tipografia** | Inter (UI) + InterDisplay (display) |
| **Personalidade visual** | Limpa, densa (padrão SaaS), acessível (WCAG AA), dark mode obrigatório |
| **Filosofia** | Hierarquia por **elevação/luminosidade** (nunca preto/branco puro); marca com **parcimônia** (≤10% da tela) |

---

## 2. Princípios de design

1. **Elevação por luminosidade** no dark mode (página `solid-1` < card `solid-2` < input `solid-3`); **nunca preto puro**.
2. **Sem branco puro na página** (light) — página off-white, cards brancos.
3. **Cor de marca ≤ 10% da tela** — só CTAs, links e tab ativa.
4. **Grid de 8pt** para todo espaçamento.
5. **Proximidade (Gestalt):** padding interno < margem externa.
6. **Borda OU sombra** — nunca os dois no mesmo elemento.
7. **Densidade SaaS:** corpo em `text-sm` (14px), não 16px.
8. **Máx. 3 pesos por tela:** 400 / 500 / 600.
9. **Status nunca só por cor:** ícone + cor + texto.
10. **Mobile-first.**
11. **WCAG 2.1 AA:** contraste 4.5:1 texto, 3:1 componentes.
12. **`prefers-reduced-motion`** respeitado.

---

## 3. Cor

### Marca
| Papel | Light | Dark |
|-------|-------|------|
| Primária | `#2dc46f` | `#25d366` |
| Hover | `#008c70` | `#4de598` |
| Sobre a primária | `#ffffff` | `#ffffff` |

### Neutros (escala `slate`)
| Step | Light | Dark | Uso |
|------|-------|------|-----|
| 1 | `#ffffff` | `#0b141a` | Fundo raiz |
| 2 | `#f9fafb` | `#111b21` | Superfície sutil |
| 3 | `#f0f2f5` | `#202c33` | Painel / header |
| 4 | `#e9edef` | `#233138` | Borda fraca |
| 6 | `#d1d7db` | `#374045` | Borda forte |
| 9 | `#8696a0` | `#8696a0` | Ícone muted |
| 11 | `#667781` | `#8696a0` | **Texto secundário** |
| 12 | `#111b21` | `#e9edef` | **Texto primário** |

Hierarquia de texto: primário `slate-12` · secundário `slate-11` · muted `slate-10` · desabilitado `slate-8`.

### Semânticas (sempre com ícone + texto)
| Papel | Light | Dark | Fundo sutil (light → dark) |
|-------|-------|------|----------------------------|
| Success | `#2dc46f` | `#25d366` | `#d9fdd3` → `#005c4b` |
| Warning | `#ffc53d` | `#ffc53d` | botão `#ffdd8d` |
| Error | `#e54666` | `#e54666` | `#fed7d7` → `#5a2122` |
| Info | `#2dc46f` | `#53bdeb` | `#d9fdd3` → `#005c4b` |

### Dark mode
Classe `.dark` no root troca todas as CSS custom properties de uma vez (light em `:root`, dark em `.dark`). Nunca preto puro — usar `#0b141a` / `#111b21` / `#202c33`.

*(Escalas completas de 12 steps — iris/verde, ruby, amber, teal, violet — na seção 11.)*

---

## 4. Logo

| Asset | Tipo | Uso | URL |
|-------|------|-----|-----|
| Horizontal light | símbolo + wordmark | fundo **claro** | `…/brand-assets/logo.svg` |
| Horizontal dark | símbolo + wordmark | fundo **escuro** | `…/brand-assets/logo_dark.svg` |
| Símbolo light | só símbolo (1:1) | fundo claro | `…/brand-assets/logo_thumbnail.svg` |
| Símbolo branco | só símbolo branco | fundo escuro/colorido | `…/brand-assets/logo_thumbnail-branca.svg` |
| **Símbolo vetor** | vetor verde limpo | **favicon / app icon / avatar** | `…/brand-assets/logo_thumbnail2.svg` |

(base = `https://chat.simplexsolucoes.com.br`)

**Pareamento:** light → `logo.svg` + `logo_thumbnail.svg`; dark → `logo_dark.svg` + `logo_thumbnail-branca.svg`; ícone pequeno → `logo_thumbnail2.svg`.

**Regras:** clear-space ≥ 25% da altura/lado · mínimo 120px de largura (horizontal) ou 16px (símbolo) · nunca distorcer (horizontal ≈ 3.2:1, símbolo 1:1) · sobre o verde, elementos brancos.

> ⚠️ **Limitação:** `logo.svg`, `logo_dark.svg`, `logo_thumbnail.svg` e `logo_thumbnail-branca.svg` são SVGs que **embrulham PNG** (raster) — não escalam sem perda. O único vetor verde real é `logo_thumbnail2.svg`. Para grande formato, **revetorizar**.

---

## 5. Tipografia

- **Inter** (UI) e **InterDisplay** (display) — variáveis, pesos 100–900, self-hosted (WOFF2).
- **Fallback:** `-apple-system, system-ui, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Tahoma, Arial, sans-serif`.
- **Escala:** corpo = `text-sm` **14px** (densidade SaaS); `text-xxs` 10px (custom); títulos `text-lg font-semibold tracking-tight`; KPIs `text-2xl font-bold tabular-nums`.
- **Pesos:** 400 corpo / 500 interativo / 600 título (máx. 3 por tela). Pesos finos custom: 420, 440, 460, 520.

---

## 6. Iconografia

- Ícones animados **Lottie** (lottie-web, renderer SVG, biblioteca useAnimations).
- **Hover-only** em sidebar/tabs (nunca loop); dark mode com `dark:invert`.
- Tamanhos: 14px (tabs), 20px (cards), 24px (botões). Máx. 5–8 simultâneos. `prefers-reduced-motion` → frame estático.
- **Nunca `hover:scale`** → usar `transition-shadow hover:shadow-md`.

---

## 7. Espaçamento, layout e elevação

- **Grid 8pt.** Card `p-5`/`p-6` · gap entre cards `gap-4` · entre seções `gap-8` · input `px-3 py-2` · página `p-4 md:p-6` · form `max-w-2xl mx-auto` · sidebar `w-64`.
- **Border-radius (Tailwind default):** `lg` 8px / `xl` 12px em botões/inputs/cards.
- **Sombras custom:** `shadow-overlay` (`0 8px 30px rgba(0,0,0,.12), 0 2px 8px rgba(0,0,0,.06)`) p/ modais; `shadow-dropdown` (`0 4px 16px rgba(0,0,0,.08), 0 1px 4px rgba(0,0,0,.04)`) p/ menus. Borda **ou** sombra, nunca os dois.
- **Breakpoints:** `xs` **480** · `sm` 640 · `md` 768 · `lg` 1024 · `xl` 1280 · `2xl` 1536 · `3xl` **1900** (xs e 3xl são custom).

---

## 8. Padrões de componente

- **Botão primary:** `bg-n-brand text-white rounded-lg px-4 py-2 font-medium hover:brightness-95` · foco `focus-visible:ring-2 focus-visible:ring-offset-2`.
- **Botão secondary:** `border border-n-weak text-n-slate-12 hover:bg-n-alpha-1`. **Ghost:** `text-n-slate-11 hover:bg-n-alpha-1 p-2 rounded-lg`.
- **Card:** `rounded-xl border border-n-weak bg-white dark:bg-n-solid-2 p-5` · hover `transition-shadow hover:shadow-md`.
- **Input:** `border border-n-weak rounded-lg px-3 py-2 text-sm bg-white dark:bg-n-solid-3` · foco `focus:ring-1 focus:ring-n-brand`.
- **Tab ativa:** sublinhado 2px + `font-semibold` + `text-n-brand`; inativa `text-n-slate-10 hover:text-n-slate-12`.
- **Sidebar ativa:** fill `bg-n-alpha-2 font-medium` (não border-left).
- **Empty state:** ícone `text-n-slate-9 size-12` + título `text-base font-medium` + descrição `text-sm text-n-slate-11` + **1** CTA primário.

---

## 9. Contrato de tokens — colar em outro projeto

```css
:root {
  --brand: 45 196 111;            /* #2dc46f */  --brand-hover: 0 140 112;   /* #008c70 */
  --slate-1: 255 255 255;  --slate-2: 249 250 251; --slate-3: 240 242 245; --slate-4: 233 237 239;
  --slate-6: 209 215 219;  --slate-9: 134 150 160; --slate-11: 102 119 129; --slate-12: 17 27 33;
  --background-color: 255 255 255; --surface-1: 240 242 245;
  --border-weak: 233 237 239;      --border-strong: 209 215 219;
  --success: 45 196 111; --warning: 255 197 61; --error: 229 70 102; --info: 45 196 111;
}
.dark {
  --brand: 37 211 102;            /* #25d366 */  --brand-hover: 77 229 152;  /* #4de598 */
  --slate-1: 11 20 26;   --slate-2: 17 27 33;   --slate-3: 32 44 51;  --slate-4: 35 49 56;
  --slate-6: 55 64 69;   --slate-9: 134 150 160; --slate-11: 134 150 160; --slate-12: 233 237 239;
  --background-color: 17 27 33;  --surface-1: 11 20 26;
  --border-weak: 42 57 66; --border-strong: 55 64 69;
  --success: 37 211 102; --warning: 255 197 61; --error: 229 70 102; --info: 83 189 235;
}
```

```js
// tailwind.config.js
const a = v => `rgb(var(${v}) / <alpha-value>)`;
module.exports = {
  darkMode: 'class',
  theme: {
    screens: { xs:'480px', sm:'640px', md:'768px', lg:'1024px', xl:'1280px', '2xl':'1536px', '3xl':'1900px' },
    extend: {
      colors: { brand:a('--brand'), bg:a('--background-color'), surface:a('--surface-1'),
        slate:{1:a('--slate-1'),2:a('--slate-2'),3:a('--slate-3'),4:a('--slate-4'),6:a('--slate-6'),9:a('--slate-9'),11:a('--slate-11'),12:a('--slate-12')},
        success:a('--success'), warning:a('--warning'), error:a('--error'), info:a('--info') },
      fontFamily: { inter:['Inter','sans-serif'], interDisplay:['InterDisplay','sans-serif'] },
      fontWeight: { 420:'420',440:'440',460:'460',520:'520' },
      fontSize:  { xxs:'0.625rem' },
      boxShadow: { overlay:'0 8px 30px rgba(0,0,0,.12),0 2px 8px rgba(0,0,0,.06)', dropdown:'0 4px 16px rgba(0,0,0,.08),0 1px 4px rgba(0,0,0,.04)' },
    },
  },
};
```

**Pegadinhas:** tokens `rgb(var(--x)/<alpha-value>)` aceitam opacidade (`/50`); os com alpha embutido não. Spacing/radius/z-index = Tailwind default → **fixe a versão do Tailwind**.

---

## 10. Do / Don't

| ✅ Do | ❌ Don't |
|------|---------|
| Off-white na página, branco nos cards | Branco/preto puro |
| Corpo `text-sm` (14px) | `text-base` como corpo |
| Borda **ou** sombra | Borda **e** sombra |
| Hover de card por sombra | `hover:scale` / reflow |
| Status = ícone + cor + texto | Status só por cor |
| Marca ≤ 10% da tela | Marca dominando a tela |
| Lottie hover-only (≤ 5–8) | Lottie em loop em sidebar |
| `focus-visible:ring-2` | `outline-none` sem foco visível |

---

## 11. Escalas completas de cor

Step 9 = cor sólida principal · 11 = texto · 3–4 = fundos sutis. (`iris`/`blue`/`teal` = verde de marca tonalizado.)

**Verde de marca (`iris`):** 3 `#d9fdd3`/`#083d31` · 4 `#b8f1e0`/`#005c4b` · 9 `#2dc46f`/`#25d366` · 10 `#008c70`/`#4de598` · 11 `#006c55`/`#86f0bc` · 12 `#004d3a`/`#d9fdd3`

**Error (`ruby`):** 3 `#feeaed`/`#3a141e` · 9 `#e54666`/`#e54666` · 10 `#dc3b5d`/`#ec5a72` · 11 `#ca244d`/`#ff949d`

**Warning (`amber`):** 3 `#fff7c2`/`#302008` · 9 `#ffc53d`/`#ffc53d` · 10 `#ffba18`/`#ffd60a` · 11 `#ab6400`/`#ffca16`

**Accent (`teal`):** 3 `#d4f2ea`/`#083d31` · 9 `#2dc46f`/`#25d366` · 11 `#006c55`/`#86f0bc`

**Violet (raro):** 3 `#f4f0fe`/`#291f43` · 9 `#6e56cf`/`#6e56cf` · 11 `#6555b7`/`#a999ec`

**Neutro `slate` completo (light/dark):** 1 `#ffffff`/`#0b141a` · 2 `#f9fafb`/`#111b21` · 3 `#f0f2f5`/`#202c33` · 4 `#e9edef`/`#233138` · 5 `#d9dbdf`/`#2a3942` · 6 `#d1d7db`/`#374045` · 7 `#c7c9cc`/`#4a5459` · 8 `#a8abaf`/`#6b7377` · 9 `#8696a0`/`#8696a0` · 10 `#667781`/`#aebac1` · 11 `#667781`/`#8696a0` · 12 `#111b21`/`#e9edef`

---

*Spec de marca SPX. Cor primária `#2dc46f` · Inter/InterDisplay · dark mode `.dark`. Assets em `https://chat.simplexsolucoes.com.br/brand-assets/`.*
