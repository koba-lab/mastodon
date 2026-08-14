import { resolve } from 'node:path';

import type { StorybookConfig } from '@storybook/react-vite';

const config: StorybookConfig = {
  // ikatodon: VRT (Chromatic) 用に、ikadon の Story だけをビルドに含めたい場合が
  // ある。上流 Story も一緒にアップロードすると、撮影対象外にした Story が
  // 前回ビルドの BROKEN ステータスを引き継ぎ続け、UI Tests が恒久的に赤くなる
  // ため（detail: docs/ikadon-theme.md の「VRT (Chromatic)」節）。
  // 未設定時は上流と完全に同じ挙動。
  stories: [
    process.env.IKADON_STORIES_ONLY
      ? '../app/javascript/**/*.ikadon.stories.@(ts|tsx)'
      : '../app/javascript/**/*.stories.@(js|jsx|mjs|ts|tsx)',
  ],
  addons: [
    '@storybook/addon-docs',
    '@storybook/addon-a11y',
    '@storybook/addon-vitest',
  ],
  framework: {
    name: '@storybook/react-vite',
    options: {},
  },
  staticDirs: [
    './static',
    // We need to manually specify the assets because of the symlink in public/sw.js
    ...[
      'avatars',
      'emoji',
      'headers',
      'sounds',
      'badge.png',
      'loading.gif',
      'loading.png',
      'oops.gif',
      'oops.png',
    ].map((path) => ({ from: `../public/${path}`, to: `/${path}` })),
    { from: '../app/javascript/images/logo.svg', to: '/custom-emoji/logo.svg' },
  ],
  viteFinal(config) {
    // For an unknown reason, Storybook does not use the root
    // from the Vite config so we need to set it manually.
    config.root = resolve(import.meta.dirname, '../app/javascript');
    return config;
  },
};

export default config;
