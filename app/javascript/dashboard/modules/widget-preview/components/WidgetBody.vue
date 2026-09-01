<!-- As duas bolhas de exemplo. Nao recebem mais `config`: a cor da marca chega
     pelas custom properties do wrapper (`--w-brand` / `--w-on-brand`), que sao
     as MESMAS que o servidor emite. Passar a cor por prop era o caminho pelo
     qual o preview conseguia mostrar uma cor que o widget nao usa.

     Bloco 2.03 — a FORMA tambem deixou de ser literal aqui. Antes esta tela
     escrevia `rounded-[1.25rem] rounded-br-[0.25rem] text-sm shadow
     max-w-[85%]`: quatro numeros proprios, e tres deles CONTRADIZIAM o widget
     que a tela promete mostrar (4 px de canto contra 6 px, 14/20 de corpo
     contra 15/22, e uma sombra que o bloco 2.03 tirou do balao). O mixin
     `widget-shape` ja chega aqui pelo `.wp-tokens` de `Widget.vue`; o que
     faltava era esta metade consumi-lo. Ver o `<style>` no fim do arquivo. -->
<template>
  <div class="h-[calc(2rem*10)] px-4 overflow-y-auto">
    <div>
      <div>
        <div
          class="wp-bubble-row wp-bubble-row--user items-end flex justify-end mb-1 mt-0 text-end"
        >
          <div
            class="wp-bubble wp-bubble--user bg-w-brand text-w-on-brand px-4 py-3"
          >
            <p class="m-0">
              {{ $t('INBOX_MGMT.WIDGET_BUILDER.BODY.USER_MESSAGE') }}
            </p>
          </div>
        </div>
      </div>

      <div class="wp-bubble-row wp-bubble-row--agent">
        <div
          class="wp-bubble wp-bubble--agent px-4 py-3 inline-block text-wp-text bg-wp-surface-2"
        >
          <div>
            <p class="m-0">
              {{ $t('INBOX_MGMT.WIDGET_BUILDER.BODY.AGENT_MESSAGE') }}
            </p>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped lang="scss">
/* Zero valor proprio: os seis vem de `@mixin widget-shape`
   (`widget/assets/scss/_tokens_values.scss`), aplicado em `.wp-tokens` no
   ancestral — custom property herda, entao o preview le exatamente os numeros
   que `_tokens.scss` da ao widget de verdade.

   Sem `@apply`, e nao por gosto: o aceite do bloco e
   `getComputedStyle(bolha).boxShadow === 'none'`, e `@apply shadow-none` emite
   a cadeia `var(--tw-ring-offset-shadow,0 0 #0000), …`, que o navegador computa
   como `rgba(0, 0, 0, 0) 0px 0px 0px 0px`. So `box-shadow: none` computa
   `none`, e quem escreve `none` aqui e o token. */
.wp-bubble-row {
  max-width: var(--w-bubble-max-width);
}

/* Logico, nao fisico: a linha do visitante encosta no lado do FIM, que e a
   direita em LTR e a esquerda em RTL. Era `ml-auto` + `text-right`, que nao
   viravam. O canto de origem dos baloes abaixo segue a mesma regra, e por isso
   o espelho RTL do preview e medido em `bubble-geometry.check.mjs`. */
.wp-bubble-row--user {
  margin-inline-start: auto;
}

.wp-bubble {
  border-radius: var(--w-bubble-radius);
  box-shadow: var(--w-bubble-shadow);
  font-size: var(--w-bubble-font-size);
  line-height: var(--w-bubble-line-height);
  max-width: 100%;
}

/* Depois de `.wp-bubble` de proposito: mesma especificidade, quem vem por
   ultimo quebra o canto que aponta para o autor. */
.wp-bubble--user {
  border-end-end-radius: var(--w-bubble-radius-tail);
}

.wp-bubble--agent {
  border-end-start-radius: var(--w-bubble-radius-tail);
}
</style>
