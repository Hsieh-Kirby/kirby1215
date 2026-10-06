import argparse
import json
import re
from pathlib import Path

from docx import Document


FULLWIDTH_DIGITS = str.maketrans("０１２３４５６７８９", "0123456789")
HEADING_PATTERN = re.compile(r"^([０-９0-9]+)[ \u3000]*(\D.+)$")


def load_episodes(path: Path):
    document = Document(path)
    episodes = []
    current = None

    for paragraph in document.paragraphs:
        text = paragraph.text.strip()
        if paragraph.style.name == "Heading 1":
            match = HEADING_PATTERN.match(text)
            if not match:
                raise ValueError(f"無法辨識的標題：{text}")
            current = {
                "episode": int(match.group(1).translate(FULLWIDTH_DIGITS)),
                "title": match.group(2).strip(),
                "paragraphs": [],
            }
            episodes.append(current)
        elif text and current is not None:
            current["paragraphs"].append(text)

    numbers = [item["episode"] for item in episodes]
    expected = list(range(1, 201))
    if numbers != expected:
        raise ValueError(f"逸話篇編號不完整或順序錯誤：{numbers}")
    return episodes


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("docx", type=Path)
    parser.add_argument("--start", type=int, default=1)
    parser.add_argument("--end", type=int, default=200)
    parser.add_argument("--summary", action="store_true")
    args = parser.parse_args()

    episodes = load_episodes(args.docx)
    if args.summary:
        result = {
            "count": len(episodes),
            "numbers_ok": [item["episode"] for item in episodes] == list(range(1, 201)),
            "first": episodes[:3],
            "last": episodes[-3:],
        }
    else:
        result = [
            item
            for item in episodes
            if args.start <= item["episode"] <= args.end
        ]
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
