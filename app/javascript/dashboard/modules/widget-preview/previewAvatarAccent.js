/**
 * Cor do avatar de iniciais DENTRO do preview do widget.
 *
 * Por que este arquivo existe. `next/avatar/Avatar.vue` escolhe a cor das
 * iniciais por `name.length % 6` sobre uma paleta de hex CRAVADOS. Com
 * "Site da Simplex" (15 caracteres) o sorteio cai no par teal
 * `#ccf3ea` / `#008573`, que da **3,8187:1** — abaixo dos 4,5:1 da WCAG AA
 * (medido no Chromium; o axe-core acusa `color-contrast`, "insufficient color
 * contrast of 3.81"). Antes o preview passava `name="C"`, de um caractere, que
 * caia noutro par por acaso: o defeito nao entrou por uma cor, entrou por um
 * NOME — e um sorteio por comprimento de nome nao tem piso de contraste, entao
 * qualquer nome novo pode voltar a cair num par que reprova.
 *
 * Por isso o preview FIXA o par, e o fixa em TOKEN, nunca em hex: `--slate-4` e
 * `--slate-12` sao reapontados por `.wp-theme-light` / `.wp-theme-dark`
 * (`Widget.vue`), de modo que o avatar acompanha o tema do PREVIEW — o que o
 * cliente escolheu — e nao o do painel. E consumir a custom property e' o
 * oposto de copiar a paleta: e' a mesma fonte unica que o D4 estabeleceu.
 *
 * `darkBg` / `darkText` repetem as mesmas vars de proposito. O `Avatar` aplica
 * `dark:!bg-[var(--dark-bg)]` pela classe `.dark` do PAINEL; apontando as duas
 * pontas para a mesma custom property, quem decide a cor continua sendo o
 * escopo do preview e o painel escuro nao sequestra o avatar do widget claro.
 *
 * O piso de 4,5:1 nos dois temas do widget e' verificado em
 * `specs/previewAvatarAccent.spec.js`, contra os valores reais de
 * `widget/assets/scss/_tokens_values.scss`.
 */
export const PREVIEW_AVATAR_ACCENT = Object.freeze({
  bg: 'rgb(var(--slate-4))',
  text: 'rgb(var(--slate-12))',
  darkBg: 'rgb(var(--slate-4))',
  darkText: 'rgb(var(--slate-12))',
});

export default PREVIEW_AVATAR_ACCENT;
