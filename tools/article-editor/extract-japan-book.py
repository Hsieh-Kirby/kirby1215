import argparse
import json
import re
from pathlib import Path


PART_FILES = [
    (1, "第一部分　與日本之緣.md"),
    (2, "第二部分　研究日本人.md"),
    (3, "第三部分　從歷史發展看日本人.md"),
    (4, "第四部分　日本人的思考模式.md"),
    (5, "第五部分　理論篇.md"),
]


def split_front_matter(text):
    lines = text.replace("\r\n", "\n").split("\n")
    if not lines or lines[0].strip() != "---":
        raise ValueError("文章缺少 YAML front matter")
    end = next(i for i in range(1, len(lines)) if lines[i].strip() == "---")
    return lines[1:end], lines[end + 1 :]


def value_from_front_matter(lines, key):
    prefix = key + ":"
    for line in lines:
        if line.startswith(prefix):
            return line[len(prefix) :].strip().strip('"')
    return ""


def parse_heading(line):
    candidate = line.strip()
    if "**" not in candidate or not re.match(r"^(?:\d|\*\*\d)", candidate):
        return None
    candidate = candidate.replace("**", "")
    candidate = re.sub(r"\[\[\d+\]\]\([^)]*\)", "", candidate)
    match = re.match(r"^(\d+(?:-\d+)?)(?:\.\s*|\s*)(\D.+)$", candidate)
    if not match:
        return None
    return match.group(1), match.group(2).strip()


def load_chapters(posts_root):
    chapters = []
    parts = []
    for part, filename in PART_FILES:
        path = posts_root / filename
        front_matter, body = split_front_matter(path.read_text(encoding="utf-8-sig"))
        part_title = value_from_front_matter(front_matter, "title")
        original_url = value_from_front_matter(front_matter, "original_url")
        parts.append({
            "part": part,
            "title": part_title,
            "file": filename,
            "original_url": original_url,
        })

        current = None
        order = 0
        for line in body:
            heading = parse_heading(line)
            if heading:
                order += 1
                current = {
                    "part": part,
                    "part_title": part_title,
                    "chapter": heading[0],
                    "chapter_order": order,
                    "title": heading[1],
                    "paragraph_lines": [],
                }
                chapters.append(current)
            elif current is not None:
                current["paragraph_lines"].append(line.rstrip())

        for chapter in [item for item in chapters if item["part"] == part]:
            lines = chapter.pop("paragraph_lines")
            while lines and not lines[0].strip():
                lines.pop(0)
            while lines and not lines[-1].strip():
                lines.pop()
            chapter["body"] = "\n".join(lines)

        chapters = [item for item in chapters if item["body"].strip()]

    return parts, chapters


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("posts_root", type=Path)
    parser.add_argument("--start", type=int, default=1)
    parser.add_argument("--end", type=int, default=999)
    parser.add_argument("--summary", action="store_true")
    args = parser.parse_args()

    parts, chapters = load_chapters(args.posts_root)
    if args.summary:
        result = {
            "parts": parts,
            "chapter_count": len(chapters),
            "chapters": [
                {key: value for key, value in item.items() if key != "body"}
                for item in chapters
            ],
        }
    else:
        result = chapters[args.start - 1 : args.end]
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
