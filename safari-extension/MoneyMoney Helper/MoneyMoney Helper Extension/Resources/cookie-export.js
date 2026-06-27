/**
 * @typedef {Object} BankConfig
 * @property {string} id
 * @property {string} label
 * @property {RegExp} matchHost
 * @property {string[]} domains
 * @property {string[]} origins
 * @property {string} [sessionHost]
 * @property {string[]} critical
 * @property {string[]} allowDuplicateNames
 * @property {string[]} priority
 */

/**
 * @typedef {Object} CookieEntry
 * @property {string} name
 * @property {string} value
 * @property {string} [domain]
 * @property {string} [path]
 */

/**
 * @param {string} hostname
 * @param {Record<string, BankConfig>} banks
 * @returns {BankConfig | null}
 */
export function detectBank(hostname, banks) {
  const host = hostname.replace(/^www\./, '');
  for (const bank of Object.values(banks)) {
    if (bank.matchHost.test(host)) {
      return bank;
    }
  }
  return null;
}

/**
 * @param {CookieEntry[]} cookies
 * @param {BankConfig} bank
 */
export function formatCookieExport(cookies, bank) {
  const pairs = [];
  const usedNames = new Set();

  for (const dupName of bank.allowDuplicateNames) {
    cookies
      .filter((cookie) => cookie.name === dupName)
      .forEach((cookie) => pairs.push(`${cookie.name}=${cookie.value}`));
    if (cookies.some((cookie) => cookie.name === dupName)) {
      usedNames.add(dupName);
    }
  }

  for (const name of bank.priority) {
    if (usedNames.has(name)) {
      continue;
    }
    const match = cookies.find((cookie) => cookie.name === name);
    if (match) {
      pairs.push(`${name}=${match.value}`);
      usedNames.add(name);
    }
  }

  const rest = cookies
    .filter((cookie) => !usedNames.has(cookie.name))
    .sort((a, b) => a.name.localeCompare(b.name));
  for (const cookie of rest) {
    pairs.push(`${cookie.name}=${cookie.value}`);
    usedNames.add(cookie.name);
  }

  return `COOKIE:${pairs.join(';')}`;
}

/**
 * @param {CookieEntry[]} cookies
 * @param {BankConfig} bank
 */
export function missingCritical(cookies, bank) {
  return bank.critical.filter(
    (name) => !cookies.some((cookie) => cookie.name === name),
  );
}

/**
 * @param {BankConfig} bank
 * @param {CookieEntry[]} cookies
 * @param {string} tabHost
 */
export function buildHint(bank, cookies, tabHost) {
  if (missingCritical(cookies, bank).length === 0) {
    return '';
  }
  if (bank.sessionHost && tabHost !== bank.sessionHost) {
    return `Bitte ${bank.sessionHost} öffnen (eingeloggt, Kontoseite).`;
  }
  if (bank.id === 'mlp') {
    return 'Vertragsübersicht auf vue.mlp.de öffnen, dann erneut exportieren.';
  }
  if (bank.id === 'fidelity') {
    return 'Portfolio Summary öffnen, „Don\'t ask again on this device“ bei MFA.';
  }
  if (bank.id === 'boa') {
    return 'Kontoübersicht auf secure.bankofamerica.com öffnen.';
  }
  const missing = missingCritical(cookies, bank);
  return `Fehlende Cookies: ${missing.join(', ')}`;
}

/**
 * @param {import('./config.js').browserApi} api
 * @param {BankConfig} bank
 * @returns {Promise<CookieEntry[]>}
 */
export async function collectCookies(api, bank) {
  /** @type {Map<string, CookieEntry>} */
  const merged = new Map();

  /**
   * @param {chrome.cookies.Cookie} item
   */
  function cookieKey(item) {
    return `${item.name}|${item.domain}|${item.path}|${item.storeId ?? ''}`;
  }

  async function addFromQuery(details) {
    let list = [];
    try {
      list = await api.cookies.getAll(details);
    } catch {
      return;
    }
    for (const item of list) {
      if (!item?.name) {
        continue;
      }
      merged.set(cookieKey(item), {
        name: item.name,
        value: item.value,
        domain: item.domain,
        path: item.path,
      });
    }
  }

  for (const domain of bank.domains) {
    await addFromQuery({ domain: domain.replace(/^\./, '') });
  }

  for (const origin of bank.origins) {
    await addFromQuery({ url: `${origin}/` });
  }

  return Array.from(merged.values());
}
