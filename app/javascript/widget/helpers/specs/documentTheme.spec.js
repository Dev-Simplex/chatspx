/**
 * Mecanismo de aceite do bloco 2.10 — a metade que vive no DOCUMENTO.
 *
 * ACEITE (§2.2): «classe no `<html>`, `color-scheme` no `:root` … trocar o tema
 * do SO reflete **sem remount**».
 *
 * O `color-scheme` em si é CSS estático (`_tokens.scss`, `:root` e
 * `:root.dark`) e por isso é medido no navegador de verdade, em
 * `spec/e2e/widget/darkMode.spec.js` — `getComputedStyle` de um Chromium real é
 * a única forma honesta de assertar cascata. Aqui fica a parte que é JS: quem
 * põe e tira a classe do `<html>`, e se ela ACOMPANHA a fonte reativa.
 */
import { ref, nextTick, effectScope } from 'vue';
import {
  applyDocumentTheme,
  watchDocumentTheme,
  DARK_CLASS,
} from '../documentTheme';

describe('2.10 — classe de tema no elemento raiz do documento', () => {
  afterEach(() => {
    document.documentElement.classList.remove(DARK_CLASS);
  });

  it('acrescenta a classe quando prefere escuro', () => {
    expect(applyDocumentTheme(true)).toBe(true);
    expect(document.documentElement.classList.contains(DARK_CLASS)).toBe(true);
  });

  it('remove a classe quando prefere claro', () => {
    document.documentElement.classList.add(DARK_CLASS);

    expect(applyDocumentTheme(false)).toBe(false);
    expect(document.documentElement.classList.contains(DARK_CLASS)).toBe(false);
  });

  it('não derruba nada quando não há documento', () => {
    // O widget é código de terceiro dentro do site do cliente: uma exceção não
    // tratada aqui cairia no `window.onerror` dele.
    expect(() => applyDocumentTheme(true, undefined)).not.toThrow();
    expect(applyDocumentTheme(true, {})).toBe(false);
  });
});

describe('2.10 — a classe acompanha a fonte reativa (sem remount)', () => {
  let escopo;

  beforeEach(() => {
    escopo = effectScope();
  });

  afterEach(() => {
    escopo.stop();
    document.documentElement.classList.remove(DARK_CLASS);
  });

  const ligar = fonte => escopo.run(() => watchDocumentTheme(fonte));

  it('aplica o valor inicial sem esperar por uma troca', async () => {
    const prefere = ref(true);
    ligar(prefere);
    await nextTick();

    expect(document.documentElement.classList.contains(DARK_CLASS)).toBe(true);
  });

  it('acompanha claro → escuro → claro na MESMA ligação', async () => {
    // Esta é a asserção que reprova a forma ingênua
    // `watch(fonte, applyDocumentTheme, { immediate: true })`: o `watch` chama
    // o callback com `(novo, antigo)`, o `antigo` cai no parâmetro `doc`, e da
    // SEGUNDA chamada em diante `doc` é um booleano — `doc?.documentElement` é
    // `undefined` e a função sai sem fazer nada. Ou seja, funcionaria na
    // abertura e pararia justamente na troca de tema.
    const prefere = ref(false);
    ligar(prefere);
    await nextTick();
    expect(document.documentElement.classList.contains(DARK_CLASS)).toBe(false);

    prefere.value = true;
    await nextTick();
    expect(document.documentElement.classList.contains(DARK_CLASS)).toBe(true);

    prefere.value = false;
    await nextTick();
    expect(document.documentElement.classList.contains(DARK_CLASS)).toBe(false);
  });

  it('para de escutar quando o escopo é encerrado', async () => {
    const prefere = ref(false);
    ligar(prefere);
    await nextTick();

    escopo.stop();
    prefere.value = true;
    await nextTick();

    expect(document.documentElement.classList.contains(DARK_CLASS)).toBe(false);
  });
});
