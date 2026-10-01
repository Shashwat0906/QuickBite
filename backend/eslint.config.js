'use strict';
// Flat config without extra packages: the rules that catch real bugs.
const nodeGlobals = Object.fromEntries(
  ['require', 'module', 'exports', 'process', 'console', 'Buffer', '__dirname', 'setTimeout', 'clearTimeout',
    'setInterval', 'clearInterval', 'fetch', 'URL', 'URLSearchParams', 'AbortController', 'structuredClone']
    .map((g) => [g, 'readonly']),
);

module.exports = [
  {
    files: ['**/*.js'],
    languageOptions: { ecmaVersion: 2023, sourceType: 'commonjs', globals: nodeGlobals },
    rules: {
      'no-undef': 'error',
      'no-unused-vars': ['error', { argsIgnorePattern: '^_', caughtErrors: 'none' }],
      'no-unreachable': 'error',
      'no-dupe-keys': 'error',
      'no-const-assign': 'error',
      'no-self-assign': 'error',
      'no-redeclare': 'error',
      'prefer-const': 'error',
      eqeqeq: ['error', 'smart'],
    },
  },
  { ignores: ['node_modules/**'] },
];
