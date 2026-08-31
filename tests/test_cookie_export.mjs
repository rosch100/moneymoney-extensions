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
import { parseBankConfig } from '../browser-extension/config.js';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const banksRaw = JSON.parse(
  readFileSync(join(root, 'browser-extension/cookie-export-banks.json'), 'utf8'),
);
const banks = parseBankConfig(banksRaw);

const fidelity = banks.fidelity;
const mlp = banks.mlp;

assert.equal(detectBank('digital.fidelity.com', banks)?.id, 'fidelity');
assert.equal(detectBank('untrusted.fidelity.com', banks), null);
assert.equal(detectBank('unknown.example', banks), null);

const formatted = formatCookieExport(
  [
    { name: 'VUSESSIONID', value: 'a' },
    { name: 'VUSESSIONID', value: 'b' },
    { name: 'BIGipServervue.mlp.de', value: 'pool' },
  ],
  mlp,
);
assert.ok(formatted.startsWith('COOKIE:'));
assert.ok(formatted.includes('VUSESSIONID=a;VUSESSIONID=b'));
assert.ok(!formatted.includes(','));

assert.deepEqual(missingCritical([{ name: 'ATC', value: '1' }], fidelity), ['_abck']);
assert.equal(exportBlockReason([{ name: 'ATC', value: '1' }], ['_abck'], []), 'missing');
assert.equal(exportBlockReason([], fidelity.critical, ['https://digital.fidelity.com']), 'permission');
assert.equal(exportBlockReason([{ name: 'ATC', value: '1' }, { name: '_abck', value: '2' }], [], ['https://login.fidelity.com']), 'partial');
assert.equal(
  exportBlockReason([{ name: 'ATC', value: '1' }, { name: '_abck', value: '2' }], [], []),
  null,
);

assert.ok(buildHint(fidelity, ['ATC'], 'www.fidelity.com').includes('digital.fidelity.com'));
assert.equal(buildHint(fidelity, [], 'digital.fidelity.com'), '');

const mockApi = {
  cookies: {
    getAll: async (details) => {
      if ('url' in details && details.url?.includes('digital.fidelity.com')) {
        return [{ name: 'ATC', value: '1', domain: 'digital.fidelity.com', path: '/' }];
      }
      if (
        ('domain' in details && details.domain === 'login.fidelity.com')
        || ('url' in details && details.url?.includes('login.fidelity.com'))
      ) {
        return [{ name: '_abck', value: '2', domain: 'login.fidelity.com', path: '/' }];
      }
      return [];
    },
  },
};

const result = await collectCookies(mockApi, fidelity);
assert.ok(result.cookies.some((c) => c.name === 'ATC'));
assert.ok(result.cookies.some((c) => c.name === '_abck'));
assert.deepEqual(result.failedOrigins, []);

const deniedApi = {
  cookies: {
    getAll: async () => {
      throw new Error('denied');
    },
  },
};
const failResult = await collectCookies(deniedApi, {
  ...fidelity,
  origins: ['https://digital.fidelity.com'],
});
assert.equal(failResult.cookies.length, 0);
assert.deepEqual(failResult.failedOrigins, ['https://digital.fidelity.com']);

const domainDeniedApi = {
  cookies: {
    getAll: async (details) => {
      if ('domain' in details) {
        throw new Error('domain query denied');
      }
      return [];
    },
  },
};
const domainFailResult = await collectCookies(domainDeniedApi, {
  ...fidelity,
  origins: ['https://digital.fidelity.com'],
});
assert.equal(domainFailResult.cookies.length, 0);
assert.deepEqual(domainFailResult.failedOrigins, ['https://digital.fidelity.com']);

const partialDomainDeniedApi = {
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
};
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
    missingCritical(partialDomainFailResult.cookies, fidelity),
    partialDomainFailResult.failedOrigins,
  ),
  'missing',
);

const partialUrlDeniedApi = {
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
};
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
    missingCritical(partialUrlFailResult.cookies, fidelity),
    partialUrlFailResult.failedOrigins,
  ),
  'partial',
);

console.log('ALL COOKIE EXPORT JS TESTS PASSED');
