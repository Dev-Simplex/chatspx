import {
  getLoadingStatus,
  parseAPIErrorResponse,
  setLoadingStatus,
  throwErrorMessage,
  parseLinearAPIErrorResponse,
} from '../api';

describe('#getLoadingStatus', () => {
  it('returns correct status', () => {
    expect(getLoadingStatus({ fetchAPIloadingStatus: true })).toBe(true);
  });
});

describe('#setLoadingStatus', () => {
  it('set correct status', () => {
    const state = { fetchAPIloadingStatus: true };
    setLoadingStatus(state, false);
    expect(state.fetchAPIloadingStatus).toBe(false);
  });
});

describe('#parseAPIErrorResponse', () => {
  it('returns correct values', () => {
    expect(
      parseAPIErrorResponse({
        response: { data: { message: 'Error Message [message]' } },
      })
    ).toBe('Error Message [message]');

    expect(
      parseAPIErrorResponse({
        response: { data: { error: 'Error Message [error]' } },
      })
    ).toBe('Error Message [error]');

    expect(parseAPIErrorResponse('Error: 422 Failed')).toBe(
      'Error: 422 Failed'
    );
  });
});

describe('#throwErrorMessage', () => {
  it('throws correct error', () => {
    const errorFn = function throwErrorMessageFn() {
      throwErrorMessage({
        response: { data: { message: 'Error Message [message]' } },
      });
    };
    expect(errorFn).toThrow('Error Message [message]');
  });

  it('preserves error metadata for downstream handling', () => {
    try {
      throwErrorMessage({
        response: {
          status: 422,
          data: {
            code: 'captain_api_key_missing',
            message: 'Missing API key',
            field: 'openai_api_key',
          },
        },
      });
    } catch (error) {
      expect(error.message).toBe('Missing API key');
      expect(error.code).toBe('captain_api_key_missing');
      expect(error.status).toBe(422);
      expect(error.details).toEqual({
        code: 'captain_api_key_missing',
        message: 'Missing API key',
        field: 'openai_api_key',
      });
    }
  });
});

describe('#parseLinearAPIErrorResponse', () => {
  it('returns correct values', () => {
    expect(
      parseLinearAPIErrorResponse(
        {
          response: {
            data: {
              error: {
                errors: [
                  {
                    message: 'Error Message [message]',
                  },
                ],
              },
            },
          },
        },
        'Default Message'
      )
    ).toBe('Error Message [message]');
  });
});
