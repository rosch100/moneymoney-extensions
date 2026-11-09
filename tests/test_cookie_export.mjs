#!/usr/bin/env node
/**
 * Unit-Tests für browser-extension/cookie-export.js
 * Run: node tests/test_cookie_export.mjs
 */

import assert from 'node:assert/strict';
import {
  buildHint,
  collectCookies,
  detectBank,
  exportBlockReason,
  formatCookieExport,
  missingCritical,
} from '../browser-extension/cookie-export.js';
import {
  collectCookies as collectSafariCookies,
  detectBank as detectSafariBank,
} from '../safari-extension/MoneyMoney Helper/MoneyMoney Helper Extension/Resources/cookie-export.js';
import { parseBankConfig as parseSafariBankConfig } from '../safari-extension/MoneyMoney Helper/MoneyMoney Helper Extension/Resources/config.js';
import { parseBankConfig } from '../browser-extension/config.js';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const banksRaw = JSON.parse(
  readFileSync(join(root, 'browser-extension/cookie-export-banks.json'), 'utf8'),
);
const banks = parseBankConfig(banksRaw);
const safariBanksRaw = JSON.parse(
  readFileSync(
    join(
      root,
      'safari-extension/MoneyMoney Helper/MoneyMoney Helper Extension/Resources/cookie-export-banks.json',
    ),
    'utf8',
  ),
);
const safariBanks = parseSafariBankConfig(safariBanksRaw);

const fidelity = banks.fidelity;
const safariBoa = safariBanks.boa;

assert.deepEqual(
  safariBoa.critical,
  ['SMSESSION', 'SSOTOKEN'],
  'safariBoa.critical.containsOnlySessionCookies',
);
assert.ok(
  safariBoa.priority.includes('bm_sv'),
  'safariBoa.priority.includesBmSv',
);
assert.ok(
  safariBoa.origins.includes('https://bankofamerica.com'),
  'safariBoa.origins.includeApexDomain',
);
assert.equal(
  detectSafariBank('bankofamerica.com', safariBanks),
  safariBanks.boa,
  'detectBank.acceptsConfiguredParentDomain',
);

assert.equal(detectBank('digital.fidelity.com', banks)?.id, 'fidelity');
assert.equal(detectBank('untrusted.fidelity.com', banks), null);
assert.equal(detectBank('unknown.example', banks), null);

assert.deepEqual(missingCritical([{ name: 'ATC', value: '1' }], fidelity), ['_abck']);
assert.equal(
  exportBlockReason([{ name: 'ATC', value: '1' }], []),
  null,
  'missingCookies.doNotBlockExport',
);
assert.equal(exportBlockReason([], ['https://digital.fidelity.com']), 'permission');
assert.equal(exportBlockReason([{ name: 'ATC', value: '1' }, { name: '_abck', value: '2' }], ['https://login.fidelity.com']), 'partial');
assert.equal(
  exportBlockReason([{ name: 'ATC', value: '1' }, { name: '_abck', value: '2' }], []),
  null,
);

assert.equal(
  buildHint(fidelity, ['ATC'], 'www.fidelity.com'),
  'Bitte digital.fidelity.com öffnen (eingeloggt, Kontoseite).',
);
assert.equal(buildHint(fidelity, [], 'digital.fidelity.com'), '');

const DEFAULT_STORES = [{ id: 'persistent-1', tabIds: [1] }];

/**
 * Ergänzt eine Browser-API um Cookie-Speicher (Safari ab macOS 26 verlangt
 * eine Abfrage mit storeId).
 * @param {{ cookies: Record<string, unknown> }} api
 * @param {Array<{ id: string, tabIds: number[] }>} [stores]
 */
function withStores(api, stores = DEFAULT_STORES) {
  return {
    cookies: {
      getAllCookieStores: async () => stores,
      ...api.cookies,
    },
  };
}

const mockApi = withStores({
  cookies: {
    getAll: async (details) => {
      if (
        'url' in details
        && details.url
        && new URL(details.url).hostname === 'digital.fidelity.com'
      ) {
        return [{ name: 'ATC', value: '1', domain: 'digital.fidelity.com', path: '/' }];
      }
      if (
        ('domain' in details && details.domain === 'login.fidelity.com')
        || (
          'url' in details
          && details.url
          && new URL(details.url).hostname === 'login.fidelity.com'
        )
      ) {
        return [{ name: '_abck', value: '2', domain: 'login.fidelity.com', path: '/' }];
      }
      return [];
    },
  },
});

const result = await collectCookies(mockApi, fidelity);
assert.ok(result.cookies.some((c) => c.name === 'ATC'));
assert.ok(result.cookies.some((c) => c.name === '_abck'));
assert.deepEqual(result.failedOrigins, []);

const deniedApi = withStores({
  cookies: {
    getAll: async () => {
      throw new Error('denied');
    },
  },
});
const failResult = await collectCookies(deniedApi, {
  ...fidelity,
  origins: ['https://digital.fidelity.com'],
});
assert.equal(failResult.cookies.length, 0);
assert.deepEqual(failResult.failedOrigins, ['https://digital.fidelity.com']);

const domainDeniedApi = withStores({
  cookies: {
    getAll: async (details) => {
      if ('domain' in details) {
        throw new Error('domain query denied');
      }
      return [];
    },
  },
});
const domainFailResult = await collectCookies(domainDeniedApi, {
  ...fidelity,
  origins: ['https://digital.fidelity.com'],
});
assert.equal(domainFailResult.cookies.length, 0);
assert.deepEqual(domainFailResult.failedOrigins, ['https://digital.fidelity.com']);

const partialDomainDeniedApi = withStores({
  cookies: {
    getAll: async (details) => {
      if ('domain' in details) {
        throw new Error('domain query denied');
      }
      return [{
        name: 'ATC',
        value: 'partial',
        domain: '.fidelity.com',
        path: '/',
        storeId: '0',
      }];
    },
  },
});
const partialDomainFailResult = await collectCookies(partialDomainDeniedApi, {
  ...fidelity,
  origins: ['https://digital.fidelity.com'],
});
assert.equal(partialDomainFailResult.cookies.length, 1);
assert.deepEqual(
  partialDomainFailResult.failedOrigins,
  ['https://digital.fidelity.com'],
);
assert.equal(
  exportBlockReason(
    partialDomainFailResult.cookies,
    partialDomainFailResult.failedOrigins,
  ),
  'partial',
);

const partialUrlDeniedApi = withStores({
  cookies: {
    getAll: async (details) => {
      if ('url' in details) {
        throw new Error('url query denied');
      }
      return [
        { name: 'ATC', value: '1', domain: '.fidelity.com', path: '/' },
        { name: '_abck', value: '2', domain: '.fidelity.com', path: '/' },
      ];
    },
  },
});
const partialUrlFailResult = await collectCookies(partialUrlDeniedApi, {
  ...fidelity,
  origins: ['https://digital.fidelity.com'],
});
assert.equal(partialUrlFailResult.cookies.length, 2);
assert.deepEqual(
  partialUrlFailResult.failedOrigins,
  ['https://digital.fidelity.com'],
);
assert.equal(
  exportBlockReason(
    partialUrlFailResult.cookies,
    partialUrlFailResult.failedOrigins,
  ),
  'partial',
);

const storeQueries = [];
const storeApi = {
  cookies: {
    getAllCookieStores: async () => [
      { id: 'persistent-1', tabIds: [] },
      { id: 'persistent-2', tabIds: [42] },
    ],
    getAll: async (details) => {
      storeQueries.push(details);
      if (
        details.storeId === 'persistent-2'
        && (
          details.url === 'https://digital.fidelity.com/'
          || details.domain === 'digital.fidelity.com'
        )
      ) {
        return [{ name: 'ATC', value: '1', domain: '.fidelity.com', path: '/' }];
      }
      return [];
    },
  },
};
const storeResult = await collectCookies(
  storeApi,
  fidelity,
  'https://digital.fidelity.com/portfolio',
  42,
);
assert.ok(storeResult.cookies.some((cookie) => cookie.name === 'ATC'));
assert.ok(
  storeQueries.length > 0
    && storeQueries.every((query) => query.storeId === 'persistent-2'),
  'storeQuery.usesActiveTabStore',
);

const noStoreApi = {
  cookies: {
    getAll: async () => [
      { name: 'ATC', value: '1', domain: '.fidelity.com', path: '/' },
    ],
  },
};
const noStoreResult = await collectCookies(noStoreApi, fidelity);
assert.equal(noStoreResult.cookies.length, 0);
assert.equal(
  exportBlockReason(noStoreResult.cookies, noStoreResult.failedOrigins),
  'permission',
  'missingCookieStoresApi.blocksExport',
);

const safariCookieQueries = [];
const safariApi = withStores({
  cookies: {
    getAll: async (details) => {
      safariCookieQueries.push(details);
      return [];
    },
  },
});
await collectSafariCookies(
  safariApi,
  safariBoa,
  'https://secure.bankofamerica.com/myaccounts/details/card/account-details.go',
);
assert.ok(
  safariCookieQueries.some((query) => query.domain === 'bankofamerica.com'),
  'safariCookies.queriesParentDomain',
);

console.log('ALL COOKIE EXPORT JS TESTS PASSED');
