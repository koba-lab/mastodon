import type { Meta, StoryObj } from '@storybook/react-vite';

import HomeIcon from '@/material-icons/400-24px/home-fill.svg?react';
import BellIcon from '@/material-icons/400-24px/notifications-fill.svg?react';
import PublicIcon from '@/material-icons/400-24px/public.svg?react';

import { modes } from '../../../../../../.storybook/modes';

import { ColumnLoading } from './column_loading';
import { ColumnsArea } from './columns_area';

// ikadon はマルチカラム（上級者 UI）全体の地をグレーのギザギザで塗り、
// 各カラムの上端だけを角丸にする。上流の Story 一覧にはレイアウト容器を
// 撮るものが1本もなかったため新規に追加している。
// 実際のタイムラインは API 依存が重いため、データを持たない ColumnLoading
// （Column + ColumnHeader + scrollable の骨格）を子に並べて地の塗りと
// カラムヘッダーの色分けを確認する。
const meta = {
  component: ColumnsArea,
  title: 'Ikadon/ColumnsArea',
  parameters: {
    layout: 'fullscreen',
    chromatic: {
      modes: {
        ikadon: modes.darkTheme,
      },
    },
    // ColumnsArea は state.settings.columns を素の配列として参照するが、
    // デフォルトの Redux state には HYDRATE 前提でこのキー自体が存在しない。
    // 何も指定しないと columns.map で例外になるため、空配列を明示する。
    state: {
      settings: {
        columns: [],
      },
    },
  },
} satisfies Meta<typeof ColumnsArea>;

export default meta;

type Story = StoryObj<typeof meta>;

export const MultiColumn: Story = {
  args: {
    children: (
      <ColumnLoading title='Home' icon='home' iconComponent={HomeIcon} />
    ),
  },
  render: () => (
    // 実際のアプリでは .layout-multiple-columns が祖先要素、.ui がその子孫要素として
    // 別ノードになる（ikadon の `.layout-multiple-columns .ui { background: ... }` は
    // 子孫セレクタ）。同じ div に両方のクラスを付けると一致しないため入れ子にする。
    <div className='layout-multiple-columns'>
      <div className='ui'>
        <ColumnsArea>
          <ColumnLoading
            title='Home'
            icon='home'
            iconComponent={HomeIcon}
            active
            multiColumn
          />
          <ColumnLoading
            title='Notifications'
            icon='bell'
            iconComponent={BellIcon}
            multiColumn
          />
          <ColumnLoading
            title='Local timeline'
            icon='globe'
            iconComponent={PublicIcon}
            multiColumn
          />
        </ColumnsArea>
      </div>
    </div>
  ),
};
