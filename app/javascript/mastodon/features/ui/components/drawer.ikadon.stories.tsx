import type { Meta, StoryObj } from '@storybook/react-vite';

import HomeIcon from '@/material-icons/400-24px/home-fill.svg?react';
import MenuIcon from '@/material-icons/400-24px/menu.svg?react';
import NotificationsIcon from '@/material-icons/400-24px/notifications-fill.svg?react';
import PublicIcon from '@/material-icons/400-24px/public.svg?react';
import { Icon } from 'mastodon/components/icon';

import { modes } from '../../../../../../.storybook/modes';

import DrawerLoading from './drawer_loading';

// マルチカラム（上級者 UI）の「ドロワー」。実体は features/compose/index.tsx の
// Compose コンポーネントが multiColumn プロパティを受け取ったときに描画する
// .drawer 以下の DOM（ナビゲーションタブ・検索・投稿フォーム）で、上流には
// 独立した drawer.tsx は存在しない。
//
// この Compose を Storybook でそのまま描画することは断念した。投稿フォーム内の
// LanguageDropdown / UploadButton が `mastodon/initial_state` の
// モジュールレベル定数（`languages` / `me` など。Rails が埋め込む
// window 上の初期データを import 時点で1度だけ読む設計）に依存しており、
// これは Redux の state ではないため Story 側からは一切上書きできない
// （`window.initialState` を import より前に用意する手段が preview.tsx を
// 触らずには存在しない）。ハイドレーションを前提にした上流の設計そのものが
// 原因であり、ikadon 側のコードには起因しないため、上流には手を入れず、
// 代わりに以下の代替構成で「ドロワー」を撮っている。
//
// - DrawerLoading（features/ui/components/drawer_loading.jsx）: Compose の
//   lazy-load 中に実際に表示される、依存のない本物のプレースホルダー。
//   .drawer / .drawer__pager / .drawer__inner に対する ikadon の濃色ギザギザ地・
//   角丸を確認できる。
// - ヘッダーのジグザグ装飾（.drawer__header、ピンクのジグザグ画像）は
//   DrawerLoading には無いため、実際の Compose と同じ className 構造
//   （drawer__header / drawer__tab）だけを軽量に再現して並べている。
//   本物は <Link>/<a> なので、ここでも <a> を使う（.drawer__tab は上流 CSS 上
//   リンク要素前提でボタンのブラウザ既定背景を打ち消していないため、
//   <button> にすると地の色が隠れてしまう）。ナビゲーションは行わない
//   見た目確認専用のダミーなので、jsx-a11y/anchor-is-valid を明示的に無効化する。
const meta = {
  title: 'Ikadon/Drawer',
  parameters: {
    layout: 'fullscreen',
    chromatic: {
      modes: {
        ikadon: modes.darkTheme,
      },
    },
  },
} satisfies Meta;

export default meta;

type Story = StoryObj<typeof meta>;

export const MultiColumnDrawer: Story = {
  render: () => (
    // columns_area.ikadon.stories.tsx と同じ理由で .layout-multiple-columns と
    // .ui は別ノードに分ける。
    <div className='layout-multiple-columns'>
      <div className='ui'>
        {/* eslint-disable jsx-a11y/anchor-is-valid -- 見た目確認専用のダミーナビゲーション */}
        <nav className='drawer__header' aria-label='Quick links'>
          <a className='drawer__tab' title='Menu' aria-label='Menu'>
            <Icon id='bars' icon={MenuIcon} />
          </a>
          <a className='drawer__tab' title='Home' aria-label='Home'>
            <Icon id='home' icon={HomeIcon} />
          </a>
          <a
            className='drawer__tab'
            title='Notifications'
            aria-label='Notifications'
          >
            <Icon id='bell' icon={NotificationsIcon} />
          </a>
          <a
            className='drawer__tab'
            title='Local timeline'
            aria-label='Local timeline'
          >
            <Icon id='globe' icon={PublicIcon} />
          </a>
        </nav>
        {/* eslint-enable jsx-a11y/anchor-is-valid */}

        <DrawerLoading />
      </div>
    </div>
  ),
};
