import { useImageListRetry } from '../loadWithRetry';

// N-04: a miniatura de uma midia recem-chegada pode ser pedida antes de o arquivo chegar ao disco. Numa
// lista (faixa de midias, quadros do album), cada peca tenta de novo antes de desistir.
describe('useImageListRetry', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('keeps the original src until the first error', () => {
    const { retrySrc } = useImageListRetry();
    expect(retrySrc('a', '/thumb.png')).toBe('/thumb.png');
  });

  it('asks again with a new src after the backoff', () => {
    const { retrySrc, onLoadError, hasFailed } = useImageListRetry();

    onLoadError('a');
    expect(retrySrc('a', '/thumb.png')).toBe('/thumb.png');

    vi.advanceTimersByTime(1000);
    expect(retrySrc('a', '/thumb.png')).toBe('/thumb.png?retry=1');
    expect(retrySrc('a', '/thumb.png?w=250')).toBe('/thumb.png?w=250&retry=1');
    expect(hasFailed('a')).toBe(false);
  });

  it('gives up after the last attempt, one piece at a time', () => {
    const { onLoadError, hasFailed } = useImageListRetry();

    onLoadError('a');
    vi.advanceTimersByTime(1000);
    onLoadError('a');
    vi.advanceTimersByTime(2000);
    onLoadError('a');

    expect(hasFailed('a')).toBe(true);
    expect(hasFailed('b')).toBe(false);
  });
});
