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
});

export const APPEARANCE_ENUMS = Object.freeze({
  theme: ['light', 'auto', 'dark'],
  position: ['left', 'right'],
  launcher_type: ['standard', 'expanded_bubble'],
  panel_style: ['standard', 'flat'],
  launcher_icon: ['default', 'image', 'agent_photo'],
});
