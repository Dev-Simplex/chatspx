import { describe, it, expect, vi, beforeEach } from 'vitest';

import {
  fireTakeoverConfetti,
  setConfettiImporterForTesting,
  resetConfettiForTesting,
} from '../useConfetti';

describe('useConfetti', () => {
  let confettiMock;
  let importerMock;

  beforeEach(() => {
    // canvas-confetti só chega no lote D-L5 — o spec SEMPRE mocka o import
    // dinâmico via test seam (a lib não existe em node_modules ainda).
    confettiMock = vi.fn();
    importerMock = vi.fn().mockResolvedValue({ default: confettiMock });
    resetConfettiForTesting();
    setConfettiImporterForTesting(importerMock);
  });

  it('lazy-loads canvas-confetti and fires the subtle takeover burst', async () => {
    const fired = await fireTakeoverConfetti();

    expect(fired).toBe(true);
    expect(importerMock).toHaveBeenCalledTimes(1);
    expect(confettiMock).toHaveBeenCalledTimes(1);
    expect(confettiMock).toHaveBeenCalledWith({
      particleCount: 30,
      scalar: 0.8,
      spread: 60,
      origin: { y: 0.8 },
      disableForReducedMotion: true,
    });
  });

  it('always passes disableForReducedMotion (DD-10)', async () => {
    await fireTakeoverConfetti();

    expect(confettiMock).toHaveBeenCalledWith(
      expect.objectContaining({ disableForReducedMotion: true })
    );
  });

  it('fires only ONCE per session: second call is a no-op', async () => {
    const first = await fireTakeoverConfetti();
    const second = await fireTakeoverConfetti();

    expect(first).toBe(true);
    expect(second).toBe(false);
    expect(importerMock).toHaveBeenCalledTimes(1);
    expect(confettiMock).toHaveBeenCalledTimes(1);
  });

  it('guards against double-fire on concurrent calls while loading', async () => {
    const [first, second] = await Promise.all([
      fireTakeoverConfetti(),
      fireTakeoverConfetti(),
    ]);

    expect([first, second].filter(Boolean)).toHaveLength(1);
    expect(importerMock).toHaveBeenCalledTimes(1);
    expect(confettiMock).toHaveBeenCalledTimes(1);
  });

  it('degrades gracefully when the import fails (lib not installed yet)', async () => {
    importerMock.mockRejectedValue(
      new Error("Cannot find module 'canvas-confetti'")
    );

    await expect(fireTakeoverConfetti()).resolves.toBe(false);
    expect(confettiMock).not.toHaveBeenCalled();
  });

  it('resetConfettiForTesting re-arms the session guard', async () => {
    await fireTakeoverConfetti();
    resetConfettiForTesting();
    setConfettiImporterForTesting(importerMock);

    const fired = await fireTakeoverConfetti();

    expect(fired).toBe(true);
    expect(confettiMock).toHaveBeenCalledTimes(2);
  });
});
