// Uma entrada com prefixo `!` em requiredPermissions é uma NEGAÇÃO: quem tiver
// aquela permissão não passa, mesmo satisfazendo alguma das entradas positivas
// (ver denyPermission em constants/permissions.js). A negação vence porque este
// helper é a fonte única do menu lateral (Policy -> usePolicy) E da guarda de
// rota (routeHelpers) — mexer só num dos dois deixa a URL viva.
export const hasPermissions = (
  requiredPermissions = [],
  availablePermissions = []
) => {
  const isDenial = permission => permission.startsWith('!');

  const denied = requiredPermissions
    .filter(isDenial)
    .map(permission => permission.slice(1));
  if (denied.some(permission => availablePermissions.includes(permission))) {
    return false;
  }

  return requiredPermissions
    .filter(permission => !isDenial(permission))
    .some(permission => availablePermissions.includes(permission));
};

export const getCurrentAccount = ({ accounts } = {}, accountId = null) => {
  return accounts.find(account => Number(account.id) === Number(accountId));
};

export const getUserPermissions = (user, accountId) => {
  const currentAccount = getCurrentAccount(user, accountId) || {};
  return currentAccount.permissions || [];
};

export const getUserRole = (user, accountId) => {
  const currentAccount = getCurrentAccount(user, accountId) || {};
  if (currentAccount.custom_role_id) {
    return 'custom_role';
  }

  return currentAccount.role || 'agent';
};

/**
 * Filters and transforms items based on user permissions.
 *
 * @param {Object} items - An object containing items to be filtered.
 * @param {Array} userPermissions - Array of permissions the user has.
 * @param {Function} getPermissions - Function to extract required permissions from an item.
 * @param {Function} [transformItem] - Optional function to transform each item after filtering.
 * @returns {Array} Filtered and transformed items.
 */
export const filterItemsByPermission = (
  items,
  userPermissions,
  getPermissions,
  transformItem = (key, item) => ({ key, ...item })
) => {
  // Helper function to check if an item has the required permissions
  const hasRequiredPermissions = item => {
    const requiredPermissions = getPermissions(item);
    return (
      requiredPermissions.length === 0 ||
      hasPermissions(requiredPermissions, userPermissions)
    );
  };

  return Object.entries(items)
    .filter(([, item]) => hasRequiredPermissions(item)) // Keep only items with required permissions
    .map(([key, item]) => transformItem(key, item)); // Transform each remaining item
};
