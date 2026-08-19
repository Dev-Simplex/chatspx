import md5 from 'md5';
import Cookies from 'js-cookie';

// Bloco 5.17 — quem identifica sozinho. `phone_number` entrou: um site que so tem o telefone do
// visitante (formulario de WhatsApp, checkout por celular) nao conseguia identificar ninguem, e a
// chamada morria com "should have one of the keys [avatar_url, email, name]".
const REQUIRED_USER_KEYS = ['avatar_url', 'email', 'name', 'phone_number'];

// Bloco 5.17 — o que entra no hash de dedupe.
//
// Antes eram so os quatro de cima. Consequencia medida: mudar SO o telefone produzia o MESMO hash,
// o SDK comparava com o cookie e retornava cedo — a atualizacao NAO saia do navegador. O mesmo
// valia para empresa, cidade, pais, descricao e atributos personalizados: campos que o widget
// envia (`widget/store/modules/contacts.js:52-80`) mas que o dedupe nao enxergava.
//
// A lista tem de cobrir TUDO o que o widget manda. Um campo que o widget envia e o hash ignora e,
// por construcao, um campo que nunca atualiza depois da primeira vez.
const ALLOWED_USER_ATTRIBUTES = [
  ...REQUIRED_USER_KEYS,
  'identifier_hash',
  'company_name',
  'city',
  'country_code',
  'description',
  'signed_up_at',
  'social_profiles',
  'custom_attributes',
];

// Objeto vira texto com as chaves ORDENADAS: sem isso, o mesmo conteudo em outra ordem produziria
// hash diferente e o dedupe reenviaria a cada chamada — o defeito oposto, e igualmente silencioso.
const stableString = value => {
  if (value === null || value === undefined) return '';
  if (typeof value !== 'object') return String(value);
  if (Array.isArray(value)) return value.map(stableString).join(',');

  return Object.keys(value)
    .sort()
    .map(key => `${key}:${stableString(value[key])}`)
    .join(',');
};

export const getUserCookieName = () => {
  const SET_USER_COOKIE_PREFIX = 'cw_user_';
  const { websiteToken: websiteIdentifier } = window.$chatwoot;
  return `${SET_USER_COOKIE_PREFIX}${websiteIdentifier}`;
};

export const getUserString = ({ identifier = '', user }) => {
  const userStringWithSortedKeys = ALLOWED_USER_ATTRIBUTES.reduce(
    (acc, key) => `${acc}${key}${stableString(user[key])}`,
    ''
  );
  return `${userStringWithSortedKeys}identifier${identifier}`;
};

export const computeHashForUserData = (...args) => md5(getUserString(...args));

export const hasUserKeys = user =>
  REQUIRED_USER_KEYS.reduce((acc, key) => acc || !!user[key], false);

export const setCookieWithDomain = (
  name,
  value,
  { expires = 365, baseDomain = undefined } = {}
) => {
  const cookieOptions = {
    expires,
    sameSite: 'Lax',
    domain: baseDomain,
  };

  // if type of value is object, stringify it
  // this is because js-cookies 3.0 removed builtin json support
  // ref: https://github.com/js-cookie/js-cookie/releases/tag/v3.0.0
  if (typeof value === 'object') {
    value = JSON.stringify(value);
  }

  Cookies.set(name, value, cookieOptions);
};
