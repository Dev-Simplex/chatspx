/**
 * Mecanismo de aceite do bloco 2.16.
 *
 * ACEITE (§2.2): "3 mensagens digitadas offline chegam **em ordem** na volta;
 * nenhum evento de digitando em lote".
 */
import { createOfflineQueue } from '../queue';

const msg = content => ({ type: 'send_message', content });

describe('2.16 — a fila entrega em ordem', () => {
  it('três mensagens digitadas offline chegam na ordem em que foram escritas', async () => {
    const fila = createOfflineQueue();
    ['primeira', 'segunda', 'terceira'].forEach(t => fila.enqueue(msg(t)));

    const chegaram = [];
    // O envio demora um pouco MAIS a cada chamada: se a drenagem fosse
    // paralela, a terceira chegaria antes da primeira e o teste acusaria.
    let atraso = 0;
    const resultado = await fila.flush(item => {
      atraso += 10;
      return new Promise(resolve => {
        setTimeout(() => {
          chegaram.push(item.content);
          resolve();
        }, 30 - atraso);
      });
    });

    expect(chegaram).toEqual(['primeira', 'segunda', 'terceira']);
    expect(resultado).toEqual({ enviados: 3, restantes: 0 });
    expect(fila.size).toBe(0);
  });

  it('falha no meio para a fila e NÃO pula a mensagem que falhou', async () => {
    const fila = createOfflineQueue();
    ['a', 'b', 'c'].forEach(t => fila.enqueue(msg(t)));

    const chegaram = [];
    const resultado = await fila.flush(item => {
      if (item.content === 'b') return Promise.reject(new Error('rede'));
      chegaram.push(item.content);
      return Promise.resolve();
    });

    expect(chegaram).toEqual(['a']);
    expect(resultado).toEqual({ enviados: 1, restantes: 2 });
    expect(fila.peek().map(i => i.content)).toEqual(['b', 'c']);
  });

  it('retomar depois da falha entrega o resto, ainda em ordem', async () => {
    const fila = createOfflineQueue();
    ['a', 'b', 'c'].forEach(t => fila.enqueue(msg(t)));

    let falhar = true;
    await fila.flush(item => {
      if (falhar && item.content === 'b')
        return Promise.reject(new Error('rede'));
      return Promise.resolve();
    });

    falhar = false;
    const chegaram = [];
    const resultado = await fila.flush(item => {
      chegaram.push(item.content);
      return Promise.resolve();
    });

    expect(chegaram).toEqual(['b', 'c']);
    expect(resultado.restantes).toBe(0);
  });
});

describe('2.16 — estado transitório não entra na fila', () => {
  it('digitando é recusado, e quem chamou fica sabendo', () => {
    const recusados = [];
    const fila = createOfflineQueue({ onDrop: d => recusados.push(d) });

    expect(fila.enqueue({ type: 'typing_on' })).toBe(false);
    expect(fila.enqueue({ type: 'typing_off' })).toBe(false);

    expect(fila.size).toBe(0);
    expect(recusados.map(r => r.reason)).toEqual([
      'transitorio',
      'transitorio',
    ]);
  });

  it('nenhum evento de digitando sai em lote na volta da rede', async () => {
    const fila = createOfflineQueue();

    // O visitante digitou uma mensagem e ficou digitando: só a mensagem entra.
    fila.enqueue({ type: 'typing_on' });
    fila.enqueue(msg('oi'));
    fila.enqueue({ type: 'typing_on' });
    fila.enqueue({ type: 'typing_off' });

    const chegaram = [];
    await fila.flush(item => {
      chegaram.push(item.type);
      return Promise.resolve();
    });

    expect(chegaram).toEqual(['send_message']);
  });

  it('tipo desconhecido também não entra — a fila não é um saco de eventos', () => {
    const recusados = [];
    const fila = createOfflineQueue({ onDrop: d => recusados.push(d) });

    expect(fila.enqueue({ type: 'qualquer_coisa' })).toBe(false);
    expect(recusados[0].reason).toBe('desconhecido');
  });

  it('anexo é intenção e entra', () => {
    const fila = createOfflineQueue();

    expect(fila.enqueue({ type: 'send_attachment', file: 'x' })).toBe(true);
    expect(fila.size).toBe(1);
  });
});
