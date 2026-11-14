import js from '@eslint/js';
import tseslint from 'typescript-eslint';
import eslintConfigPrettier from 'eslint-config-prettier';
import { defineConfig } from 'eslint/config';

export default defineConfig([
  {
    files: ['src/**/*.ts'],
    rules: { semi: 'error', 'prefer-const': 'error' },
    extends: [js.configs.recommended, tseslint.configs.recommended],
  },
  eslintConfigPrettier,
]);
