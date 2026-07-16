import { getTemplateInfo } from '../templateHelper';
import { MESSAGE_TYPES } from '../constants';

const buildTemplateMessage = (
  templateParams,
  messageType = MESSAGE_TYPES.OUTGOING
) => ({
  messageType,
  additionalAttributes: { echoId: '13ca77764620', templateParams },
});

describe('getTemplateInfo', () => {
  it('returns the template name for an outgoing template message', () => {
    // Shape mirrors a real payload, post camelization by MessageList.
    const message = buildTemplateMessage({
      name: 'iniciar_conversa',
      category: 'UTILITY',
      language: 'pt_BR',
      processedParams: { body: { 1: 'Neusa' } },
    });

    expect(getTemplateInfo(message)).toEqual({ name: 'iniciar_conversa' });
  });

  it('returns null for a plain outgoing message', () => {
    expect(
      getTemplateInfo({
        messageType: MESSAGE_TYPES.OUTGOING,
        additionalAttributes: { echoId: '13ca77764620' },
      })
    ).toBeNull();
  });

  it.each([
    ['incoming', MESSAGE_TYPES.INCOMING],
    ['activity', MESSAGE_TYPES.ACTIVITY],
    ['template type', MESSAGE_TYPES.TEMPLATE],
  ])('returns null for a %s message even with templateParams', (_, type) => {
    const message = buildTemplateMessage({ name: 'iniciar_conversa' }, type);

    expect(getTemplateInfo(message)).toBeNull();
  });

  it('flags the message as a template but with no name when name is missing', () => {
    expect(
      getTemplateInfo(buildTemplateMessage({ language: 'pt_BR' }))
    ).toEqual({
      name: null,
    });
  });

  it.each([
    ['blank', '   '],
    ['a number', 42],
    ['null', null],
  ])('flags the message with no name when name is %s', (_, name) => {
    expect(getTemplateInfo(buildTemplateMessage({ name }))).toEqual({
      name: null,
    });
  });

  it('trims surrounding whitespace off the name', () => {
    expect(
      getTemplateInfo(buildTemplateMessage({ name: ' iniciar_conversa ' }))
    ).toEqual({ name: 'iniciar_conversa' });
  });

  it.each([
    ['null', null],
    ['a string', 'iniciar_conversa'],
    ['an array', [{ name: 'iniciar_conversa' }]],
  ])('returns null when templateParams is %s', (_, templateParams) => {
    expect(getTemplateInfo(buildTemplateMessage(templateParams))).toBeNull();
  });

  it('does not throw on a message with no attributes at all', () => {
    expect(getTemplateInfo()).toBeNull();
    expect(getTemplateInfo({})).toBeNull();
    expect(getTemplateInfo({ messageType: MESSAGE_TYPES.OUTGOING })).toBeNull();
  });
});
