#!/usr/bin/env python3
"""ikatodon: chromaui/action が junitReport: true で出力する JUnit XML から、
失敗した Story (error/failure 要素を持つ testcase) を抽出して Markdown の
箇条書きに変換する。

.github/workflows/chromatic.yml の "Report failed stories" ステップから呼ばれる。
XML の構造は chromatic-cli のソース (dist/chunk-*.js 内の $Nr / YNr 関数) から
確認したもので、testsuite > testcase > (error|failure) という単純な階層になっている。

ビルドを ikadon の Story だけに絞っている（.storybook/main.ts の
IKADON_STORIES_ONLY）ため、この XML に含まれる testcase は常に ikadon 由来のもの。
"""

import sys
import xml.etree.ElementTree as ET


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: chromatic_junit_summary.py <junit.xml>", file=sys.stderr)
        return 1

    tree = ET.parse(sys.argv[1])
    root = tree.getroot()
    suites = [root] if root.tag == "testsuite" else root.findall(".//testsuite")

    found = False
    for suite in suites:
        for tc in suite.findall("testcase"):
            for tag in ("error", "failure"):
                for node in tc.findall(tag):
                    found = True
                    name = tc.get("name", "?")
                    classname = tc.get("classname", "?")
                    message = node.get("message", "")
                    etype = node.get("type", "")
                    print(f"- **{classname} / {name}** ({tag}, type={etype}): {message}")

    if not found:
        print("(失敗した Story はありません)")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
