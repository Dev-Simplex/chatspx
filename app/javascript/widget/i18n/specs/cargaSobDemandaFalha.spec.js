/**
 * O caminho de FALHA do carregamento de idioma — bloco 2.18.
 *
 * Arquivo separado porque `vi.mock` é içado para o topo do módulo: para
 * derrubar o chunk de UM idioma sem derrubar os outros testes, ele precisa de
 * um arquivo só dele.
 *
 * ESTE TESTE NÃO AFIRMA AUSÊNCIA. Se o mock não pegasse, `loadLocaleMessages`
 * devolveria as mensagens reais de `th` e a asserção `toBeNull()` falharia —
 * então "passou" aqui significa que o `import()` de fato quebrou e o `catch`
 * do módulo foi exercido. Sem o `catch`, a promessa rejeita e o teste morre.
 */
import { describe, it, expect, vi, beforeEach } from 'vitest';

vi.mock('widget/i18n/locale/th.json', () => {
  throw new Error('rede caiu no chunk do idioma');
});

import { hasLocale, loadLocaleMessages } from 'widget/i18n';

describe('widget/i18n — chunk de idioma que não chega', () => {
  beforeEach(() => {
    vi.spyOn(console, 'error').mockImplementation(() => {});
  });

  it('degrada para null e registra, em vez de derrubar o painel', async () => {
    expect(hasLocale('th')).toBe(true);

    await expect(loadLocaleMessages('th')).resolves.toBeNull();

    // O silêncio é o que transforma "o widget está em inglês" num chamado sem
    // pista — o registro no console faz parte do contrato.
    expect(console.error).toHaveBeenCalledWith(
      expect.stringContaining('"th"'),
      expect.any(Error)
    );
  });
});
