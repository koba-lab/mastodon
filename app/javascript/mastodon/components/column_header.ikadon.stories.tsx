import type { Meta, StoryObj } from '@storybook/react-vite';

import HomeIcon from '@/material-icons/400-24px/home-fill.svg?react';
import BellIcon from '@/material-icons/400-24px/notifications-fill.svg?react';
import PublicIcon from '@/material-icons/400-24px/public.svg?react';

import { modes } from '../../../../.storybook/modes';

import { ColumnHeader } from './column_header';

// ikadon はカラムの種類ごとにヘッダーの色を変える（ホーム＝ライム、通知＝水色、
// ローカルタイムライン＝黄色）。この Story はその色分けと、ギザギザ地・角丸の
// 見た目を撮るためのもの。上流の Story 一覧には column_header 用のものが
// 存在しなかったため新規に追加している。
const meta = {
  component: ColumnHeader,
  title: 'Ikadon/ColumnHeader',
  parameters: {
    layout: 'fullscreen',
    // ikadon は単一固定配色（ダークテーマ）のみを持つため、追加スナップショットは
    // 1 モードに絞る。light/dark 両方を撮っても差分は生まれない。
    chromatic: {
      modes: {
        ikadon: modes.darkTheme,
      },
    },
  },
  args: {
    title: 'Home',
    active: true,
    multiColumn: true,
    icon: 'home',
    iconComponent: HomeIcon,
  },
} satisfies Meta<typeof ColumnHeader>;

export default meta;

type Story = StoryObj<typeof meta>;

export const Home: Story = {};

export const Notifications: Story = {
  args: {
    title: 'Notifications',
    icon: 'bell',
    iconComponent: BellIcon,
  },
};

export const LocalTimeline: Story = {
  args: {
    title: 'Local timeline',
    icon: 'globe',
    iconComponent: PublicIcon,
  },
};

export const Pinned: Story = {
  args: {
    ...Home.args,
    pinned: true,
    onPin: () => {
      /* noop */
    },
  },
};
