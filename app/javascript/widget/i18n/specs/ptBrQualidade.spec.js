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
});
