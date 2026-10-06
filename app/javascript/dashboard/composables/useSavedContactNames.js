import { reactive } from 'vue';
import ContactNamesAPI from 'dashboard/api/contactNames';

/**
 * Regra do produto: a partir do momento que um número está salvo no sistema,
 * toda tela que mostraria só o número mostra o nome do dono dele.
 *
 * Fonte única para isso. Cada tela pergunta pelos números que está mostrando;
 * os pedidos do mesmo instante viram UMA requisição (GET /contact_names) e o
 * resultado fica em cache para a sessão inteira.
 *
 * cache[dígitos] = { id, name } (tem ficha; name null = ficha sem nome de verdade)
 *                | null        (consultado: não está salvo)
 *                | ausente     (ainda não consultado)
 */
const cache = reactive({});
const queue = new Set();
const BATCH = 200;
let timer = null;

const digitsOf = phone => String(phone || '').replace(/\D/g, '');

const flush = async () => {
  timer = null;
  const phones = [...queue];
  queue.clear();
  for (let i = 0; i < phones.length; i += BATCH) {
    const chunk = phones.slice(i, i + BATCH);
    try {
      // eslint-disable-next-line no-await-in-loop
      const { data } = await ContactNamesAPI.get(chunk);
      chunk.forEach(phone => {
        cache[phone] = data?.contacts?.[phone] || null;
      });
    } catch {
      // Sem resposta, a tela segue mostrando o número: nada quebra.
    }
  }
};

const request = digits => {
  if (!digits || digits in cache || queue.has(digits)) return;
  queue.add(digits);
  timer = timer || setTimeout(flush, 30);
};

/**
 * Ficha salva do número: { id, name } | null (não salvo) | undefined (consultando).
 * Pode ser chamada dentro de computed: o primeiro acesso agenda a consulta.
 */
export const savedContactFor = phone => {
  const digits = digitsOf(phone);
  request(digits);
  return cache[digits];
};

/** Nome salvo do dono do número, ou null. */
export const savedNameFor = phone => savedContactFor(phone)?.name || null;

/** Depois de salvar/renomear: esquece e consulta de novo. */
export const refreshSavedContacts = phones => {
  phones.map(digitsOf).forEach(digits => {
    delete cache[digits];
    request(digits);
  });
};

/** Nome que tem letra é nome; "+55 66 9..." não identifica ninguém. */
export const isRealName = name => /\p{L}/u.test(String(name || ''));

const WHATSAPP_ID = /^(\d+)@(c\.us|s\.whatsapp\.net)$/;

/**
 * Nome para exibir de um contato: o nome dele quando é nome de verdade; senão o
 * nome salvo do dono do número (outra ficha do mesmo número, com ou sem o nono
 * dígito); senão o que já se mostrava.
 */
export const contactDisplayName = (contact, fallback = '') => {
  const name = String(contact?.name || '').trim();
  if (isRealName(name)) return name;
  const phone =
    contact?.phone_number ||
    contact?.phoneNumber ||
    String(contact?.identifier || '').match(WHATSAPP_ID)?.[1] ||
    name;
  return (phone && savedNameFor(phone)) || name || fallback;
};

/** Autor de grupo ({ name, phone }) com o nome salvo do dono do número. */
export const withSavedName = sender => {
  const saved = sender?.phone && savedNameFor(sender.phone);
  return saved ? { ...sender, name: saved } : sender;
};
