/**
 * Config do Tailwind SÓ para o widget — bloco 1.08 do redesenho.
 *
 * O PROBLEMA QUE ISTO RESOLVE
 *
 * `tailwind.config.js` declara um `content` que varre o projeto inteiro:
 * `dashboard/**`, `portal/**`, `survey/**`, `v3/**`, os `.erb` de
 * `enterprise/app/views` e os helpers/composables do dashboard. Como o CSS do
 * widget é gerado por esse mesmo config, ele recebia TODA utilitária que
 * qualquer uma dessas superfícies usa — 1.692.204 B crus para uma tela de chat
 * que o visitante baixa em rede móvel.
 *
 * A correção não toca componente nenhum: é dizer ao Tailwind, para este bundle,
 * quais arquivos de fato renderizam dentro do iframe do widget.
 *
 * COMO ELE É SELECIONADO
 *
 * Pela diretiva `@config` no topo de `widget/assets/scss/woot.scss`. Não há como
 * fazer isso pelo `postcss.config.js`, que é único e não sabe qual bundle está
 * sendo compilado. `@config` é o mecanismo oficial do Tailwind ≥ 3.2 para
 * exatamente este caso: vários bundles, um PostCSS.
 *
 * O QUE ENTRA NO `content`, E POR QUÊ
 *
 *   · `widget/**`  — o app do painel.
 *   · `shared/**`  — obrigatório. É onde vivem CSAT, chips, cards, spinner e o
 *                    botão genérico, todos renderizados DENTRO do widget. Tirar
 *                    `shared/` daqui repetiria o erro que o aceite do bloco 1.04
 *                    alerta: número bonito com a tela quebrada.
 *   · `views/widgets/**.erb` — o documento que hospeda o painel.
 *
 * O que NÃO entra é o resto do projeto. Se um componente do dashboard passar a
 * ser renderizado no widget, a classe dele vai faltar — e o jeito certo de
 * resolver é acrescentar o caminho aqui, não voltar a varrer tudo.
 *
 * O RESTO DO TEMA É HERDADO, DE PROPÓSITO
 *
 * `theme`, `plugins` e `darkMode` vêm do config raiz por spread. Duplicar o tema
 * criaria duas fontes para a mesma cor — que é o defeito que a Onda 1 inteira
 * está corrigindo. Só `content` divirge.
 */
const base = require('./tailwind.config.js');
const { icons } = require('./theme/icons');
const {
  iconsPlugin,
  getIconCollections,
} = require('@egoist/tailwindcss-icons');

module.exports = {
  ...base,
  content: [
    './app/javascript/widget/**/*.vue',
    './app/javascript/widget/**/*.js',
    './app/javascript/shared/**/*.vue',
    './app/javascript/shared/**/*.js',
    './app/views/widgets/**/*.erb',

    // ── Componentes de `dashboard/` que o WIDGET renderiza de verdade ─────────
    // Isto NÃO é o glob antigo voltando: são seis caminhos nomeados, e cada um
    // está aqui porque o fecho de imports prova que o widget o carrega.
    //
    // A cadeia, medida a partir de `entrypoints/widget.js`:
    //   router.js → views/UnreadMessages.vue → components/UnreadMessageList.vue
    //   → components/UnreadMessage.vue → dashboard/components-next/avatar/Avatar.vue
    //   → icon/Icon.vue, GalleryView.vue → button/Button.vue, spinner/Spinner.vue
    //
    // A tela de mensagens não lidas é uma das quatro que os 16 snapshots do
    // widget cobrem. Sem estes caminhos, o Tailwind não gera as classes desses
    // componentes e a tela chega SEM ESTILO — sem erro de build, sem aviso no
    // console. Foi `specs/tailwindWidgetContent.spec.js` que pegou isso.
    //
    // São ARQUIVOS EXATOS, não globs de diretório, e a diferença é grande:
    // `components-next/icon/**` traz sete arquivos — incluindo dois
    // `*.story.vue`, que nunca renderizam em produção — e custa 30.625 B só
    // ele. Nomeando `Icon.vue`, o conjunto dos seis cai de 103.903 B para
    // 71.560 B de utilitárias. Glob aqui é imprecisão paga em bytes.
    './app/javascript/dashboard/components-next/avatar/Avatar.vue',
    './app/javascript/dashboard/components-next/icon/Icon.vue',
    './app/javascript/dashboard/components-next/button/Button.vue',
    './app/javascript/dashboard/components-next/spinner/Spinner.vue',
    './app/javascript/dashboard/components-next/TeleportWithDirection.vue',
    './app/javascript/dashboard/components/widgets/conversation/components/GalleryView.vue',

    // `shared/components/ui/**` FORA. O plano (§A.1.1 ponto 25) já suspeitava
    // disso por leitura; aqui está medido: percorrendo o fecho de imports a
    // partir de `entrypoints/widget.js`, o widget alcança 206 arquivos, 47 deles
    // em `shared/` — e NENHUM em `shared/components/ui/`. Multiselect, dropdowns
    // e labels entravam no CSS do widget pelo glob, não por render, e traziam
    // 8.529 B de ícones (`i-lucide-sparkles`, `i-lucide-bot`, …) que o visitante
    // baixava sem nunca ver. `StarRating` e `EmojiPicker`, que o widget de fato
    // renderiza, ficam — os ícones deles continuam no CSS.
    '!./app/javascript/shared/components/ui/**',
  ],

  // ── `plugins` declarado, não herdado ────────────────────────────────────────
  // O spread traria `@tailwindcss/typography`, que gerava 16.536 B no CSS do
  // widget — para UM elemento: o título do CSAT, que usava `prose prose-bubble`
  // (medido: é a única ocorrência de `prose` em tudo que o widget renderiza).
  // 16 KB de estilos para h1–h6, tabelas, `pre`, `blockquote` e imagens num
  // título de uma linha é desproporcional; o CSAT recebeu, no lugar, o estilo
  // mínimo de markdown que ele realmente usa, no `<style scoped>` que já tinha.
  //
  // Os outros dois plugins ficam: `tailwindcss-animated` fornece utilitárias que
  // o widget usa, e `iconsPlugin` é o que desenha os ícones de `EmojiPicker` e
  // `StarRating`. As coleções foram reduzidas às duas que o widget referencia —
  // e, como o plugin só emite CSS de classe que aparece no `content`, isso é
  // higiene, não economia.
  plugins: [
    // eslint-disable-next-line
    require('tailwindcss-animated'),
    iconsPlugin({
      collections: {
        woot: { icons },
        ...getIconCollections(['lucide', 'ri']),
      },
    }),
  ],
};
