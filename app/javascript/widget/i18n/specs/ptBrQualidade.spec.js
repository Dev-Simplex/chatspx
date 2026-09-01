/**
 * Mecanismo de aceite do bloco 2.17 — i18n do widget.
 *
 * ACEITE (§2.2): «`grep -rn "mandat"+"ório" widget/i18n/` vazio; nenhum rótulo
 * acessível em inglês com interface em pt-BR». A palavra do aceite NÃO aparece
 * escrita por extenso em lugar nenhum deste arquivo, de propósito: o aceite é
 * um `grep` literal, e um comentário citando o termo faria o comando devolver
 * o próprio teste como se fosse um defeito.
 *
 * Este arquivo cobre a metade que é de DADOS (o conteúdo dos arquivos de
 * locale). A metade que é de MARCAÇÃO — o rótulo que o componente realmente
 * renderiza — mora em `widget/components/specs/rotulosPtBr.spec.js`, porque
 * exige montar o componente: uma chave traduzida que ninguém usa não conserta
 * rótulo nenhum, e foi exatamente esse o defeito aqui (as três chaves
 * `REQUIRED_ERROR` existiam traduzidas em 40 idiomas e o formulário mostrava
 * "Obrigatório" para todo mundo).
 */
import fs from 'fs';
import path from 'path';
import en from 'widget/i18n/locale/en.json';
import ptBR from 'widget/i18n/locale/pt_BR.json';

const LOCALE_DIR = path.resolve(__dirname, '../locale');

describe('2.17 — qualidade do i18n do widget', () => {
  describe('o anglicismo de obrigatoriedade não existe em locale nenhum', () => {
    // Varre o diretório inteiro em vez de conferir só `pt_BR.json`: o aceite é
    // `grep -rn ... widget/i18n/`, e um `pt.json` ou `pt_PT.json` futuro cairia
    // no mesmo erro sem que ninguém percebesse.
    const arquivos = fs
      .readdirSync(LOCALE_DIR)
      .filter(nome => nome.endsWith('.json'));

    it.each(arquivos)('%s não contém o anglicismo', nome => {
      const bruto = fs.readFileSync(path.join(LOCALE_DIR, nome), 'utf-8');
      const linhas = bruto
        .split('\n')
        .map((linha, i) => [i + 1, linha])
        .filter(([, linha]) => /mandat[óo]ri/i.test(linha));

      expect(linhas).toEqual([]);
    });

    it('a mensagem de nome completo usa "obrigatório"', () => {
      expect(ptBR.PRE_CHAT_FORM.FIELDS.FULL_NAME.REQUIRED_ERROR).toBe(
        'Nome completo é obrigatório'
      );
    });
  });

  describe('rótulos acessíveis novos existem nos DOIS idiomas', () => {
    // Regra da onda: toda string nova entra em `pt_BR` E em `en`. Sem esta
    // asserção, acrescentar só o pt-BR deixaria o inglês caindo na chave crua.
    const CHAVES = ['AGENT_AVATAR', 'IMAGE_ATTACHMENT'];

    // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys -- aqui a chave
    // é dado do próprio teste (a lista `CHAVES`), não uma chave montada em
    // tempo de execução; a regra existe para o segundo caso.
    it.each(CHAVES)('A11Y.%s está em en e em pt_BR', chave => {
      expect(typeof en.A11Y[chave]).toBe('string');
      expect(typeof ptBR.A11Y[chave]).toBe('string');
      expect(en.A11Y[chave].length).toBeGreaterThan(0);
      expect(ptBR.A11Y[chave].length).toBeGreaterThan(0);
      // E são de fato idiomas diferentes: copiar o inglês para o pt_BR é o
      // jeito mais comum de "traduzir" e passar num teste de presença.
      expect(ptBR.A11Y[chave]).not.toBe(en.A11Y[chave]);
    });
  });

  /**
   * A TERCEIRA entrega do título do bloco — «revisão de traduções mecânicas».
   *
   * A trilha anterior varreu `pt_BR.json`, LISTOU cinco decalques e deixou os
   * cinco, porque corrigi-los mexe nos PNG de baseline do e2e (o harness roda
   * em `locale: 'pt_BR'`). A lista virou uma pergunta em aberto; estas duas
   * varreduras a fecham e impedem que a sexta apareça.
   *
   * Duas varreduras porque são dois defeitos com formas diferentes, e uma não
   * enxerga a outra: `Segunda-Feira` não é igual ao inglês, e `Download` não
   * tem segunda palavra maiúscula.
   */
  describe('decalques do inglês', () => {
    const achatar = (objeto, prefixo = '') =>
      Object.entries(objeto).flatMap(([chave, valor]) => {
        const caminho = prefixo ? `${prefixo}.${chave}` : chave;
        if (valor && typeof valor === 'object') return achatar(valor, caminho);
        return typeof valor === 'string' ? [[caminho, valor]] : [];
      });

    it('nenhum rótulo curto usa Title Case do inglês', () => {
      // Em português só a primeira palavra e os nomes próprios vão com
      // maiúscula; `Iniciar Conversa` é o inglês desenhado com palavras
      // portuguesas. O recorte é deliberado — só RÓTULO (sem pontuação de
      // frase e com até quatro palavras) — porque em FRASE a maiúscula depois
      // de ponto é correta, e sem o recorte a varredura devolvia 19 achados,
      // 15 deles legítimos.
      const PROPRIOS = new Set([
        'chatwoot',
        'whatsapp',
        'instagram',
        'facebook',
        'telegram',
        'google',
        'messenger',
      ]);
      const ehRotulo = texto =>
        !/[.!?:;|{}]/.test(texto) && texto.split(/\s+/).length <= 4;

      const achados = achatar(ptBR)
        .filter(([, texto]) => ehRotulo(texto))
        .filter(([, texto]) =>
          texto
            // O hífen conta como fronteira: `Segunda-Feira` destoa dos outros
            // SEIS dias da semana, que já nascem minúsculos.
            .split(/[\s-]+/)
            .slice(1)
            .some(
              palavra =>
                palavra &&
                palavra !== palavra.toUpperCase() && // sigla: CNPJ, UF, DDI
                !PROPRIOS.has(palavra.toLowerCase()) &&
                palavra[0] === palavra[0].toUpperCase()
            )
        );

      expect(achados).toEqual([]);
    });

    it('nenhuma string de pt_BR é idêntica à de en', () => {
      const emIngles = new Map(achatar(en));
      const achados = achatar(ptBR).filter(
        ([caminho, texto]) => emIngles.get(caminho) === texto
      );

      expect(achados).toEqual([]);
    });

    // As cinco por extenso, para que o diff diga o que mudou sem precisar
    // reconstruir as varreduras acima de cabeça.
    it.each([
      ['START_CONVERSATION', 'Iniciar conversa'],
      ['END_CONVERSATION', 'Finalizar conversa'],
      ['DAY_NAMES.MONDAY', 'Segunda-feira'],
      ['PORTAL.POPULAR_ARTICLES', 'Artigos populares'],
      ['COMPONENTS.FILE_BUBBLE.DOWNLOAD', 'Baixar'],
    ])('%s = %s', (caminho, esperado) => {
      const valor = caminho
        .split('.')
        .reduce((atual, parte) => atual[parte], ptBR);
      expect(valor).toBe(esperado);
    });
  });
});
