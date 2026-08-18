import {
  buildGroupAuthor,
  groupAuthorLabels,
  groupAuthorStyle,
  phoneInitials,
} from '../groupAuthorPresenter';
import { UNKNOWN_AUTHOR_COLOR } from 'dashboard/helper/whatsappGroupHelper';
import ptBR from 'dashboard/i18n/locale/pt_BR/conversation.json';
import en from 'dashboard/i18n/locale/en/conversation.json';

const LABELS = {
  unknownLabel: 'Participante não identificado',
  unknownHint: 'O WhatsApp não informou quem enviou esta mensagem.',
  sentBy: 'Enviado por',
};

// Shape real gravado na ingestão (contrato `content_attributes.group_sender`).
const ROGERIO = {
  name: 'Rogerio José Da Silva',
  lid: '229480102662169',
  phone: '5566999991234',
};

describe('buildGroupAuthor', () => {
  it('returns null for a legacy message with no structured author', () => {
    expect(buildGroupAuthor(null, LABELS)).toBeNull();
  });

  it('builds label, initials and tooltip from name and phone', () => {
    const author = buildGroupAuthor(ROGERIO, LABELS);

    expect(author.label).toBe('Rogerio José Da Silva');
    expect(author.isUnknown).toBe(false);
    expect(author.initials).toBe('RS');
    // Telefone SÓ no tooltip — nunca no corpo da bolha.
    expect(author.tooltip).toBe('Rogerio José Da Silva · +55 66 9 9999-1234');
    expect(author.ariaLabel).toBe('Enviado por Rogerio José Da Silva');
  });

  it('never leaks the technical identifier (LID) into anything rendered', () => {
    const author = buildGroupAuthor(ROGERIO, LABELS);
    const rendered = [
      author.label,
      author.tooltip,
      author.ariaLabel,
      author.initials,
    ].join(' ');

    expect(rendered).not.toContain(ROGERIO.lid);
    expect(rendered).not.toContain('@lid');
  });

  it('falls back to the formatted phone when there is no name', () => {
    const author = buildGroupAuthor(
      { name: null, lid: '229480102662169', phone: '5566999991234' },
      LABELS
    );

    expect(author.label).toBe('+55 66 9 9999-1234');
    expect(author.isUnknown).toBe(false);
    // O DDD identifica de relance; o número já é o rótulo, então o tooltip não repete.
    expect(author.initials).toBe('66');
    expect(author.tooltip).toBe('+55 66 9 9999-1234');
  });

  it('marks an unidentified participant and keeps it out of the palette', () => {
    const author = buildGroupAuthor(
      { name: null, lid: '229480102662169', phone: null },
      LABELS
    );

    expect(author.isUnknown).toBe(true);
    expect(author.label).toBe('Participante não identificado');
    expect(author.initials).toBe('?');
    expect(author.color).toBe(UNKNOWN_AUTHOR_COLOR.light);
    expect(author.colorDark).toBe(UNKNOWN_AUTHOR_COLOR.dark);
    expect(author.tooltip).toBe(LABELS.unknownHint);
  });

  it('keeps the colour stable when the participant renames on WhatsApp', () => {
    const before = buildGroupAuthor(ROGERIO, LABELS);
    const after = buildGroupAuthor({ ...ROGERIO, name: 'Rogerio' }, LABELS);

    expect(after.color).toBe(before.color);
    expect(after.colorDark).toBe(before.colorDark);
  });

  it('gives light and dark variants for the same author', () => {
    const author = buildGroupAuthor(ROGERIO, LABELS);

    expect(author.color).not.toBe(author.colorDark);
    expect(author.color).toMatch(/^#[0-9a-f]{6}$/i);
    expect(author.colorDark).toMatch(/^#[0-9a-f]{6}$/i);
  });
});

describe('phoneInitials', () => {
  it('uses the Brazilian area code', () => {
    expect(phoneInitials('5566999991234')).toBe('66');
  });

  it('falls back to the last two digits for other formats', () => {
    expect(phoneInitials('12345')).toBe('45');
  });

  it('never renders an empty avatar', () => {
    expect(phoneInitials('')).toBe('#');
    expect(phoneInitials(null)).toBe('#');
  });
});

describe('groupAuthorStyle', () => {
  it('exposes both themes so the dark: variants switch on their own', () => {
    const style = groupAuthorStyle(buildGroupAuthor(ROGERIO, LABELS));

    expect(style['--group-author-color']).toMatch(/^#/);
    expect(style['--group-author-color-dark']).toMatch(/^#/);
    expect(style['--group-author-color']).not.toBe(
      style['--group-author-color-dark']
    );
  });
});

describe('groupAuthorLabels', () => {
  it('falls back to pt-BR while the i18n keys do not exist yet', () => {
    const t = key => key;
    const labels = groupAuthorLabels(t);

    expect(labels.unknownLabel).toBe('Participante não identificado');
    expect(labels.unknownHint).toContain('O WhatsApp não informou');
  });

  it('uses the translation once the key exists', () => {
    const t = key =>
      key === 'GROUP_INFO.UNKNOWN_PARTICIPANT'
        ? 'Unidentified participant'
        : key;

    expect(groupAuthorLabels(t).unknownLabel).toBe('Unidentified participant');
  });

  // Guarda contra o caminho errado: as chaves de grupo vivem na RAIZ do
  // conversation.json (ao lado de CONVERSATION), não dentro de CONVERSATION.
  it('points at keys that really exist in pt_BR and en', () => {
    [ptBR, en].forEach(messages => {
      expect(messages.GROUP_INFO?.UNKNOWN_PARTICIPANT).toBeTruthy();
      expect(messages.GROUP_INFO?.UNKNOWN_PARTICIPANT_HINT).toBeTruthy();
      expect(messages.CONVERSATION?.SENT_BY).toBeTruthy();
    });
  });
});
