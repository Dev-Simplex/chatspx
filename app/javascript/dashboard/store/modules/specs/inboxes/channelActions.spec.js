import { buildInboxData } from '../../inboxes/channelActions';

// Regressao real: a escolha de times do isolamento sumia entre a tela e o banco. O `FormData` nao
// tem tipo, entao `append(key, [16])` grava a STRING "16"; o Rails declara a chave como array e o
// strong parameters descarta o escalar EM SILENCIO — resposta 200, alerta de "salvo", nada gravado.
describe('buildInboxData', () => {
  const valores = data => key => data.getAll(key).map(String);

  it('manda cada item de um array como chave[] em vez de uma string unica', () => {
    const data = buildInboxData({ team_message_isolation_team_ids: [16, 20] });

    expect(valores(data)('team_message_isolation_team_ids[]')).toEqual([
      '16',
      '20',
    ]);
    // a forma antiga (escalar) nao pode sobrar no payload: e ela que o Rails descartava
    expect(data.get('team_message_isolation_team_ids')).toBeNull();
  });

  it('manda array vazio como um chave[] em branco, para o backend poder LIMPAR a lista', () => {
    const data = buildInboxData({ team_message_isolation_team_ids: [] });

    expect(valores(data)('team_message_isolation_team_ids[]')).toEqual(['']);
  });

  it('nao mexe em valor escalar', () => {
    const data = buildInboxData({
      name: 'Vendas',
      team_message_isolation: true,
    });

    expect(data.get('name')).toBe('Vendas');
    expect(data.get('team_message_isolation')).toBe('true');
  });

  it('mantem o comportamento de selected_feature_flags (o unico array ja tratado na mao)', () => {
    const cheio = buildInboxData({
      channel: { selectedFeatureFlags: ['a', 'b'] },
    });
    expect(valores(cheio)('channel[selected_feature_flags][]')).toEqual([
      'a',
      'b',
    ]);

    const vazio = buildInboxData({ channel: { selectedFeatureFlags: [] } });
    expect(valores(vazio)('channel[selected_feature_flags][]')).toEqual(['']);
  });

  it('aplica a mesma regra a arrays dentro de channel', () => {
    const data = buildInboxData({ channel: { allowed: [1, 2] } });

    expect(valores(data)('channel[allowed][]')).toEqual(['1', '2']);
  });
});
