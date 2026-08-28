import {
  useConversationRequiredAttributes,
  CONVERSATION_ATTRIBUTE,
  CONTACT_ATTRIBUTE,
} from '../useConversationRequiredAttributes';
import { useMapGetter } from 'dashboard/composables/store';

vi.mock('dashboard/composables/store');

const conversationDefinitions = [
  {
    attributeKey: 'priority',
    attributeDisplayName: 'Priority',
    attributeDisplayType: 'list',
    attributeValues: ['High', 'Medium', 'Low'],
    required: true,
  },
  {
    attributeKey: 'category',
    attributeDisplayName: 'Category',
    attributeDisplayType: 'text',
    attributeValues: [],
    required: true,
  },
  {
    attributeKey: 'is_urgent',
    attributeDisplayName: 'Is Urgent',
    attributeDisplayType: 'checkbox',
    attributeValues: [],
    required: true,
  },
  {
    attributeKey: 'internal_note',
    attributeDisplayName: 'Internal Note',
    attributeDisplayType: 'text',
    attributeValues: [],
    required: false,
  },
];

const contactDefinitions = [
  {
    attributeKey: 'cpf',
    attributeDisplayName: 'CPF',
    attributeDisplayType: 'text',
    attributeValues: [],
    required: true,
  },
  {
    attributeKey: 'waha_whatsapp_jid',
    attributeDisplayName: 'WhatsApp JID',
    attributeDisplayType: 'text',
    attributeValues: [],
    required: false,
    hidden: true,
  },
];

const setupMocks = ({
  conversationAttributes = conversationDefinitions,
  contactAttributes = contactDefinitions,
} = {}) => {
  useMapGetter.mockImplementation(getter => {
    if (getter === 'attributes/getConversationAttributes') {
      return { value: conversationAttributes };
    }
    if (getter === 'attributes/getContactAttributes') {
      return { value: contactAttributes };
    }
    return { value: null };
  });
};

describe('useConversationRequiredAttributes', () => {
  beforeEach(() => {
    setupMocks();
  });

  describe('requiredAttributes', () => {
    it('should only return attributes flagged as required, from both models', () => {
      const { requiredAttributes } = useConversationRequiredAttributes();

      expect(requiredAttributes.value.map(attr => attr.value)).toEqual([
        'priority',
        'category',
        'is_urgent',
        'cpf',
      ]);
    });

    it('should carry the attribute model so the consumer knows where to write', () => {
      const { requiredAttributes } = useConversationRequiredAttributes();

      expect(requiredAttributes.value[0]).toEqual({
        attributeKey: 'priority',
        attributeDisplayName: 'Priority',
        attributeDisplayType: 'list',
        attributeValues: ['High', 'Medium', 'Low'],
        required: true,
        value: 'priority',
        label: 'Priority',
        type: 'list',
        attributeModel: CONVERSATION_ATTRIBUTE,
      });
      expect(requiredAttributes.value[3].attributeModel).toBe(
        CONTACT_ATTRIBUTE
      );
    });

    it('should return an empty list when nothing is required', () => {
      setupMocks({ conversationAttributes: [], contactAttributes: [] });
      const { requiredAttributes, requiredAttributeKeys } =
        useConversationRequiredAttributes();

      expect(requiredAttributes.value).toEqual([]);
      expect(requiredAttributeKeys.value).toEqual([]);
    });

    it('should handle getters that have not loaded yet', () => {
      setupMocks({ conversationAttributes: null, contactAttributes: null });
      const { requiredAttributes } = useConversationRequiredAttributes();

      expect(requiredAttributes.value).toEqual([]);
    });
  });

  describe('requiredAttributeKeys', () => {
    it('should return the keys of every required attribute', () => {
      const { requiredAttributeKeys } = useConversationRequiredAttributes();

      expect(requiredAttributeKeys.value).toEqual([
        'priority',
        'category',
        'is_urgent',
        'cpf',
      ]);
    });
  });

  describe('checkMissingAttributes', () => {
    const filledConversation = {
      priority: 'High',
      category: 'Bug Report',
      is_urgent: true,
    };

    it('should return no missing when both models are filled', () => {
      const { checkMissingAttributes } = useConversationRequiredAttributes();

      const result = checkMissingAttributes(filledConversation, {
        cpf: '123',
      });

      expect(result.hasMissing).toBe(false);
      expect(result.missing).toEqual([]);
      expect(result.all).toHaveLength(4);
    });

    it('should look up contact attributes in the contact bag, not the conversation one', () => {
      const { checkMissingAttributes } = useConversationRequiredAttributes();

      // cpf sits in the conversation bag by mistake — still missing on the contact
      const result = checkMissingAttributes(
        { ...filledConversation, cpf: '123' },
        {}
      );

      expect(result.hasMissing).toBe(true);
      expect(result.missing).toHaveLength(1);
      expect(result.missing[0].value).toBe('cpf');
      expect(result.missing[0].attributeModel).toBe(CONTACT_ATTRIBUTE);
    });

    it('should detect missing text attributes', () => {
      const { checkMissingAttributes } = useConversationRequiredAttributes();

      const result = checkMissingAttributes(
        { priority: 'High', is_urgent: true },
        { cpf: '123' }
      );

      expect(result.hasMissing).toBe(true);
      expect(result.missing).toHaveLength(1);
      expect(result.missing[0].value).toBe('category');
    });

    it('should detect empty string values as missing', () => {
      const { checkMissingAttributes } = useConversationRequiredAttributes();

      const result = checkMissingAttributes(
        { ...filledConversation, category: '' },
        { cpf: '123' }
      );

      expect(result.hasMissing).toBe(true);
      expect(result.missing[0].value).toBe('category');
    });

    it('should handle whitespace-only values as missing', () => {
      const { checkMissingAttributes } = useConversationRequiredAttributes();

      const result = checkMissingAttributes(
        { ...filledConversation, category: '   ' },
        { cpf: '123' }
      );

      expect(result.hasMissing).toBe(true);
      expect(result.missing[0].value).toBe('category');
    });

    it('should handle null values as missing for text attributes', () => {
      const { checkMissingAttributes } = useConversationRequiredAttributes();

      const result = checkMissingAttributes(
        { ...filledConversation, category: null },
        { cpf: '123' }
      );

      expect(result.hasMissing).toBe(true);
      expect(result.missing).toHaveLength(1);
      expect(result.missing[0].value).toBe('category');
    });

    it('should consider a checkbox filled when the value is false', () => {
      const { checkMissingAttributes } = useConversationRequiredAttributes();

      const result = checkMissingAttributes(
        { ...filledConversation, is_urgent: false },
        { cpf: '123' }
      );

      expect(result.hasMissing).toBe(false);
      expect(result.missing).toEqual([]);
    });

    it('should detect a missing checkbox when the key does not exist', () => {
      const { checkMissingAttributes } = useConversationRequiredAttributes();

      const result = checkMissingAttributes(
        { priority: 'High', category: 'Bug Report' },
        { cpf: '123' }
      );

      expect(result.hasMissing).toBe(true);
      expect(result.missing).toHaveLength(1);
      expect(result.missing[0].value).toBe('is_urgent');
      expect(result.missing[0].type).toBe('checkbox');
    });

    it('should consider a checkbox filled when the key exists but the value is undefined', () => {
      const { checkMissingAttributes } = useConversationRequiredAttributes();

      const result = checkMissingAttributes(
        { ...filledConversation, is_urgent: undefined },
        { cpf: '123' }
      );

      expect(result.hasMissing).toBe(false);
      expect(result.missing).toEqual([]);
    });

    it('should not treat 0 or false as missing for non-checkbox attributes', () => {
      setupMocks({
        conversationAttributes: [
          {
            attributeKey: 'score',
            attributeDisplayName: 'Score',
            attributeDisplayType: 'number',
            attributeValues: [],
            required: true,
          },
          {
            attributeKey: 'status_flag',
            attributeDisplayName: 'Status Flag',
            attributeDisplayType: 'text',
            attributeValues: [],
            required: true,
          },
        ],
        contactAttributes: [],
      });

      const { checkMissingAttributes } = useConversationRequiredAttributes();

      const result = checkMissingAttributes({ score: 0, status_flag: false });

      expect(result.hasMissing).toBe(false);
      expect(result.missing).toEqual([]);
    });

    it('should return no missing when no attributes are required', () => {
      setupMocks({ conversationAttributes: [], contactAttributes: [] });

      const { checkMissingAttributes } = useConversationRequiredAttributes();

      const result = checkMissingAttributes({});

      expect(result.hasMissing).toBe(false);
      expect(result.missing).toEqual([]);
    });
  });

  describe('splitAttributesByModel', () => {
    it('should send each filled value to the model it belongs to', () => {
      const { requiredAttributes, splitAttributesByModel } =
        useConversationRequiredAttributes();

      const result = splitAttributesByModel(requiredAttributes.value, {
        priority: 'High',
        category: 'Bug Report',
        is_urgent: false,
        cpf: '123',
      });

      expect(result.conversation).toEqual({
        priority: 'High',
        category: 'Bug Report',
        is_urgent: false,
      });
      expect(result.contact).toEqual({ cpf: '123' });
    });

    it('should ignore keys the modal did not return', () => {
      const { requiredAttributes, splitAttributesByModel } =
        useConversationRequiredAttributes();

      const result = splitAttributesByModel(requiredAttributes.value, {
        cpf: '123',
      });

      expect(result.conversation).toEqual({});
      expect(result.contact).toEqual({ cpf: '123' });
    });

    it('should return empty buckets when there is nothing to split', () => {
      const { splitAttributesByModel } = useConversationRequiredAttributes();

      expect(splitAttributesByModel()).toEqual({
        conversation: {},
        contact: {},
      });
    });
  });
});
