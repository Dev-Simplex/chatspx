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

    // ── Nada de `dashboard/` aqui, e isso foi CONQUISTADO ────────────────────
    // Até 18/08 esta lista tinha seis caminhos de `dashboard/`, porque o widget
    // renderizava o `Avatar` de lá em três telas e ele arrastava `Icon.vue`,
    // `GalleryView.vue`, `button/Button.vue` e `spinner/Spinner.vue`. Custavam
    // 27.619 B e eram a razão de o CSS ficar em 100.717 B, acima do teto.
    // `widget/components/WAvatar.vue` os substituiu — réplica pixel a pixel do
    // subconjunto usado — e os seis caminhos puderam sair.
    // A guarda que impede a volta é `specs/tailwindWidgetContent.spec.js`, que
    // assere que nenhum `.vue` de `dashboard/` está no fecho de imports.

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
