#!/usr/bin/env python3
"""ikatodon: chromaui/action が junitReport: true で出力する JUnit XML から、
失敗した Story (error/failure 要素を持つ testcase) を抽出して Markdown の
箇条書きに変換する。

.github/workflows/chromatic.yml の "Report results" ステップから呼ばれる。
XML の構造は chromatic-cli のソース (dist/chunk-*.js 内の $Nr / YNr 関数) から
確認したもので、testsuite > testcase > (error|failure) という単純な階層になっている。

JUnit XML は onlyStoryNames で絞り込んだ後も **Storybook 全体（194件）** を含む。
Chromatic はビルドの errorCount を「このビルドの testCount のうち BROKEN の数」として
サーバー側で集計しており（chromatic-cli の GraphQL クエリで
`errorCount: testCount(statuses: [BROKEN])` と定義されている）、絞り込みで対象外にした
Story も前回ビルドのステータスを引き継いだまま集計対象に含まれる
（`actualCaptureCount` とは別に `inheritedCaptureCount` という field が存在することからも
「今回撮影した分」と「前回から引き継いだ分」が区別されているのがわかる）。
そのため上流の Story が過去に一度でも壊れていると、以後 onlyStoryNames で除外していても
errorCount は 0 にならない。

このスクリプトは "classname が Ikadon. で始まる testcase" だけを ikadon 由来の失敗として
判定し、$GITHUB_OUTPUT に ikadon_failed=true/false を書き出す。ワークフロー側は
errorCount ではなくこの値でジョブの成否を決める。
"""

import os
import sys
import xml.etree.ElementTree as ET

IKADON_PREFIX = "Ikadon."


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: chromatic_junit_summary.py <junit.xml>", file=sys.stderr)
        return 1

    tree = ET.parse(sys.argv[1])
    root = tree.getroot()
    suites = [root] if root.tag == "testsuite" else root.findall(".//testsuite")

    found = False
    ikadon_failed = False
    for suite in suites:
        for tc in suite.findall("testcase"):
            for tag in ("error", "failure"):
                for node in tc.findall(tag):
                    found = True
                    name = tc.get("name", "?")
                    classname = tc.get("classname", "?")
                    message = node.get("message", "")
                    etype = node.get("type", "")
                    if classname.startswith(IKADON_PREFIX):
                        ikadon_failed = True
                    print(f"- **{classname} / {name}** ({tag}, type={etype}): {message}")

    if not found:
        print("(失敗した Story はありません)")

    github_output = os.environ.get("GITHUB_OUTPUT")
    if github_output:
        with open(github_output, "a", encoding="utf-8") as f:
            f.write(f"ikadon_failed={'true' if ikadon_failed else 'false'}\n")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
