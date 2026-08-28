import { buildInboxData } from '../../inboxes/channelActions';

describe('#buildInboxData', () => {
  it('manda cada item de um array como key[] em vez da string "1,2,3"', () => {
    const formData = buildInboxData({
      id: 12,
      agent_message_isolation_participant_ids: [3, 7],
    });

    expect(
      formData.getAll('agent_message_isolation_participant_ids[]')
    ).toEqual(['3', '7']);
    expect(formData.get('agent_message_isolation_participant_ids')).toBeNull();
  });

  it('mantem a CHAVE presente com a lista vazia', () => {
    // Sem isto, "desmarquei todo mundo" chegaria no servidor como "nao falei de
    // lista nenhuma" e nenhuma excecao seria gravada.
    const formData = buildInboxData({
      id: 12,
      team_message_isolation_participant_ids: [],
    });

    expect(formData.getAll('team_message_isolation_participant_ids[]')).toEqual(
      ['']
    );
  });

  it('nao mexe nos valores escalares', () => {
    const formData = buildInboxData({ id: 12, agent_message_isolation: true });

    expect(formData.get('id')).toBe('12');
    expect(formData.get('agent_message_isolation')).toBe('true');
  });
});
