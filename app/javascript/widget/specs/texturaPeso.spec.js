/**
 * ACEITE DE PESO DO BLOCO 2.04: *"textura < 30 KB"*.
 *
 * O aceite é sobre o ARQUIVO, então quem o verifica lê o arquivo — não uma
 * constante escrita ao lado dele. Se alguém trocar o asset por um mais bonito e
 * mais pesado, este teste vermelhece com o número medido na mensagem, que é o
 * que faz a decisão ser deliberada em vez de acidental.
 *
 * ── Por que a textura pesava tanto, e o que a fez caber ──────────────────────
 *
 * Eram DOIS PNG — 88.534 B e 96.098 B, 184.632 B somados — com o MESMO desenho
 * de rabiscos, um em traço preto sobre branco e outro em traço branco sobre
 * preto. O peso vinha de duas escolhas: guardar a cor dentro do arquivo (o que
 * obriga a ter um arquivo por tema) e guardar em PNG uma arte de linha densa.
 *
 * Agora é UMA máscara alfa em WebP sem perda, com a cor vindo de token
 * (`--w-texture-ink`). O desenho é o mesmo; o que sai é a cor e um dos arquivos.
 */
import { readFileSync } from 'node:fs';

const TETO = 30 * 1024;
const TEXTURA = 'public/assets/images/chat-spx-texture.webp';

describe('2.04 — peso da textura da conversa', () => {
  it(`cabe em ${TETO} B`, () => {
    const bytes = readFileSync(TEXTURA).byteLength;

    expect(
      bytes,
      `${TEXTURA} tem ${bytes} B; o teto do aceite é ${TETO} B`
    ).toBeLessThan(TETO);
  });

  it('é WebP de verdade, não PNG renomeado', () => {
    // `RIFF....WEBP` é a assinatura. Um PNG com extensão trocada passaria no
    // teste de tamanho por acaso e falharia no navegador.
    const cabecalho = readFileSync(TEXTURA).subarray(0, 12);

    expect(cabecalho.subarray(0, 4).toString('ascii')).toBe('RIFF');
    expect(cabecalho.subarray(8, 12).toString('ascii')).toBe('WEBP');
  });

  it('o widget não referencia mais os dois PNG antigos', () => {
    // Eles continuam no repositório de propósito: `dashboard/.../_wa-skin.scss`
    // e o exportador de PDF de conversas os usam, e este bloco é do widget.
    // O que não pode é o WIDGET voltar a baixá-los.
    const alcance = [
      'app/javascript/widget/components/ConversationWrap.vue',
      'app/javascript/widget/views/Messages.vue',
      'app/javascript/widget/assets/scss/views/_conversation.scss',
      'app/javascript/widget/assets/scss/woot.scss',
    ].map(arquivo => readFileSync(arquivo, 'utf8'));

    alcance.forEach(conteudo => {
      expect(conteudo).not.toContain('chat-spx-background');
    });
  });
});
