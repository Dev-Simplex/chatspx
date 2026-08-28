/**
 * Os limites e enums de `widget_appearance`, do lado da tela.
 *
 * A autoridade é o servidor (`app/models/concerns/widget_appearance_schema.rb`,
 * bloco 3.18): é ele que valida o jsonb e devolve 422. Estes valores existem
 * para a tela poder avisar ANTES — e `specs/widgetAppearanceContract.spec.js`
 * lê o arquivo Ruby e falha se os dois lados se separarem.
 */
export const APPEARANCE_LIMITS = Object.freeze({
  offsetMin: 0,
  offsetMax: 200,
  launcherTextMax: 64,
  /**
   * Bloco 3.19 — o teto do byte do ícone do lançador. A tela recusa ANTES de
   * subir: mandar 400 KB para o servidor devolver 422 é meio minuto de espera
   * do administrador para um "não" que a própria tela já sabia dar.
   */
  launcherIconMaxBytes: 20480,
});

/**
 * Os tipos que o servidor aceita anexar. SVG está fora, e a ausência é decisão:
 * SVG é documento executável servido do NOSSO domínio.
 */
export const LAUNCHER_ICON_TYPES = Object.freeze(['image/webp', 'image/png']);

export const APPEARANCE_ENUMS = Object.freeze({
  theme: ['light', 'auto', 'dark'],
  position: ['left', 'right'],
  launcher_type: ['standard', 'expanded_bubble'],
  panel_style: ['standard', 'flat'],
  launcher_icon: ['default', 'image', 'agent_photo'],
});
