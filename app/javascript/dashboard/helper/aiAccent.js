/**
 * Cor própria de cada agente de IA — determinística por id, sempre na família
 * roxa (a cor de IA do produto). O fork só tem o token --violet como roxo real,
 * então usamos uma paleta curada de tons roxo/violeta/magenta/índigo com variantes
 * light e dark (strings de cor CSS), garantindo bom contraste nos dois temas.
 *
 * Uso: <Avatar :accent="aiAccent(assistant.id)" /> e aiAccentVars(id) para
 * estilizar outras superfícies via CSS custom properties.
 */
const PALETTE = [
  // violet (base da identidade de IA)
  {
    bg: 'rgb(235 228 255)',
    text: 'rgb(101 85 183)',
    darkBg: 'rgb(50 37 85)',
    darkText: 'rgb(169 153 236)',
  },
  // purple
  {
    bg: 'rgb(243 232 255)',
    text: 'rgb(139 66 178)',
    darkBg: 'rgb(44 29 58)',
    darkText: 'rgb(216 168 240)',
  },
  // indigo
  {
    bg: 'rgb(230 230 255)',
    text: 'rgb(78 75 200)',
    darkBg: 'rgb(32 32 77)',
    darkText: 'rgb(165 163 255)',
  },
  // magenta / fuchsia
  {
    bg: 'rgb(251 226 246)',
    text: 'rgb(179 48 143)',
    darkBg: 'rgb(58 29 51)',
    darkText: 'rgb(240 168 219)',
  },
  // plum
  {
    bg: 'rgb(247 225 245)',
    text: 'rgb(156 43 173)',
    darkBg: 'rgb(52 28 55)',
    darkText: 'rgb(224 168 232)',
  },
  // blue-violet
  {
    bg: 'rgb(230 233 255)',
    text: 'rgb(75 75 194)',
    darkBg: 'rgb(39 38 77)',
    darkText: 'rgb(161 158 255)',
  },
];

export const aiAccentIndex = id => {
  const n = Number(id);
  if (!Number.isFinite(n)) return 0;
  return Math.abs(Math.trunc(n)) % PALETTE.length;
};

export const aiAccent = id => PALETTE[aiAccentIndex(id)];

/**
 * Mesmas cores como CSS custom properties para usar em qualquer elemento:
 * style="..."  →  background: var(--ai-bg); color: var(--ai-text);
 * (a troca light/dark é feita pela classe `dark` no body via --ai-dark-*).
 */
export const aiAccentVars = id => {
  const a = aiAccent(id);
  return {
    '--ai-bg': a.bg,
    '--ai-text': a.text,
    '--ai-dark-bg': a.darkBg,
    '--ai-dark-text': a.darkText,
  };
};
