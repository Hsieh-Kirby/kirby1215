from __future__ import annotations

import html
import json
import re
import time
import urllib.parse
import urllib.request
import urllib.error
import uuid
import zipfile
from dataclasses import dataclass
from html.parser import HTMLParser
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "output" / "唐喬凡尼_繁體中文義大利文對照版.epub"
CACHE = ROOT / "output" / "don-giovanni-translation-cache.json"
SOURCE_API = "https://it.wikisource.org/w/api.php"
SOURCE_PAGES = [
    ("角色介紹", "Don_Giovanni/Personaggi"),
    ("第一幕", "Don_Giovanni/Atto_primo"),
    ("第二幕", "Don_Giovanni/Atto_secondo"),
]
USER_AGENT = "DonGiovanniTraditionalChineseEpub/1.0 (personal study edition)"


@dataclass
class Block:
    kind: str
    text: str


class WikisourceParser(HTMLParser):
    """Extract the semantic reading blocks from Wikisource's rendered HTML."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.blocks: list[Block] = []
        self._active: list[tuple[str, int]] = []
        self._buf: list[str] = []
        self._depth = 0
        self._skip_depth = 0

    @staticmethod
    def _classes(attrs: list[tuple[str, str | None]]) -> set[str]:
        value = dict(attrs).get("class") or ""
        return set(value.split())

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        self._depth += 1
        classes = self._classes(attrs)
        if self._skip_depth:
            self._skip_depth += 1
            return
        if classes & {"ws-noexport", "noprint", "mw-editsection"}:
            self._skip_depth = 1
            return
        kind = None
        if tag == "div" and "poem" in classes:
            kind = "dialogue"
        elif tag == "div" and "indent" in classes:
            kind = "stage"
        elif tag == "div" and "centertext" in classes:
            kind = "center"
        elif tag == "dl":
            kind = "stage"
        if kind and not self._active:
            self._active.append((kind, self._depth))
            self._buf = []
        if self._active and tag in {"br", "p", "dd", "li"}:
            self._buf.append("\n")

    def handle_startendtag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if self._active and tag == "br":
            self._buf.append("\n")

    def handle_endtag(self, tag: str) -> None:
        if self._skip_depth:
            self._skip_depth -= 1
            self._depth -= 1
            return
        if self._active and self._active[-1][1] == self._depth:
            kind, _ = self._active.pop()
            text = "\n".join(
                line.strip() for line in "".join(self._buf).splitlines() if line.strip()
            )
            text = re.sub(r"[ \t]+", " ", text).strip()
            if text and not re.fullmatch(r"\[p\.\s*\d+\]", text, re.I):
                self.blocks.append(Block(kind, text))
            self._buf = []
        self._depth -= 1

    def handle_data(self, data: str) -> None:
        if self._active and not self._skip_depth:
            self._buf.append(data)


def fetch_rendered(page: str) -> str:
    params = urllib.parse.urlencode(
        {
            "action": "parse",
            "page": page,
            "prop": "text",
            "format": "json",
            "formatversion": "2",
            "origin": "*",
        }
    )
    req = urllib.request.Request(f"{SOURCE_API}?{params}", headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=60) as response:
        return json.load(response)["parse"]["text"]


def normalize_source(blocks: list[Block]) -> list[Block]:
    out: list[Block] = []
    started = False
    for block in blocks:
        text = block.text.replace("\xa0", " ").strip()
        if re.search(r"ATTO (PRIMO|SECONDO)|PERSONAGGI", text, re.I):
            started = True
        if not started:
            continue
        text = re.sub(r"\s+([,.;:!?])", r"\1", text)
        text = re.sub(r" {2,}", " ", text)
        if text:
            out.append(Block(block.kind, text))
    return out


def load_cache() -> dict[str, str]:
    if CACHE.exists():
        return json.loads(CACHE.read_text(encoding="utf-8"))
    return {}


def save_cache(cache: dict[str, str]) -> None:
    CACHE.parent.mkdir(parents=True, exist_ok=True)
    CACHE.write_text(json.dumps(cache, ensure_ascii=False, indent=2), encoding="utf-8")


NAME_FIXES = {
    "唐璜": "唐・喬凡尼",
    "唐·喬凡尼": "唐・喬凡尼",
    "唐喬瓦尼": "唐・喬凡尼",
    "喬瓦尼": "喬凡尼",
    "萊波雷洛": "雷波雷洛",
    "萊波雷羅": "雷波雷洛",
    "唐娜安娜": "安娜",
    "唐娜·安娜": "安娜",
    "唐娜艾薇拉": "艾維拉",
    "唐娜·艾薇拉": "艾維拉",
    "埃爾維拉": "艾維拉",
    "唐·奧塔維奧": "奧塔維奧",
    "澤琳娜": "采琳娜",
    "澤莉娜": "采琳娜",
    "馬塞托": "馬賽托",
    "指揮官": "騎士長",
}


def translate_piece(text: str) -> str:
    payload = urllib.parse.urlencode(
        {"client": "gtx", "sl": "it", "tl": "zh-TW", "dt": "t", "q": text}
    ).encode("utf-8")
    req = urllib.request.Request(
        "https://translate.googleapis.com/translate_a/single",
        data=payload,
        headers={"User-Agent": USER_AGENT, "Content-Type": "application/x-www-form-urlencoded"},
    )
    for attempt in range(8):
        try:
            with urllib.request.urlopen(req, timeout=60) as response:
                result = json.load(response)
            translated = "".join(part[0] for part in result[0] if part and part[0])
            for old, new in NAME_FIXES.items():
                translated = translated.replace(old, new)
            return translated.strip()
        except urllib.error.HTTPError as exc:
            if exc.code == 429:
                return translate_piece_mymemory(text)
            if attempt == 7:
                raise
            time.sleep(2 ** attempt)
        except Exception:
            if attempt == 7:
                raise
            time.sleep(2 ** attempt)
    raise RuntimeError("translation failed")


def translate_piece_mymemory(text: str) -> str:
    """Fallback for temporary Google limits; MyMemory accepts short segments."""
    translated_parts: list[str] = []
    for piece in split_for_translation(text, limit=420):
        query = urllib.parse.urlencode({"q": piece, "langpair": "it|zh-TW"})
        req = urllib.request.Request(
            f"https://api.mymemory.translated.net/get?{query}",
            headers={"User-Agent": USER_AGENT},
        )
        with urllib.request.urlopen(req, timeout=60) as response:
            result = json.load(response)
        translated = result.get("responseData", {}).get("translatedText", "").strip()
        if not translated:
            raise RuntimeError("MyMemory returned an empty translation")
        for old, new in NAME_FIXES.items():
            translated = translated.replace(old, new)
        translated_parts.append(translated)
        time.sleep(0.35)
    return "\n".join(translated_parts)


def split_for_translation(text: str, limit: int = 3200) -> list[str]:
    lines = text.splitlines()
    chunks: list[str] = []
    current: list[str] = []
    size = 0
    for line in lines:
        if current and size + len(line) + 1 > limit:
            chunks.append("\n".join(current))
            current, size = [], 0
        current.append(line)
        size += len(line) + 1
    if current:
        chunks.append("\n".join(current))
    return chunks


def translate(text: str, cache: dict[str, str]) -> str:
    parts = []
    for piece in split_for_translation(text):
        if piece not in cache:
            cache[piece] = translate_piece(piece)
            save_cache(cache)
            time.sleep(0.8)
        parts.append(cache[piece])
    return "\n".join(parts)


def scene_title(text: str) -> str | None:
    match = re.search(r"scena\s+([ivxlcdm]+|\d+)", text, re.I)
    if not match:
        return None
    raw = match.group(1).upper()
    return f"第 {raw} 場"


def xhtml_page(title: str, body: str) -> str:
    return f'''<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="zh-Hant">
<head><title>{html.escape(title)}</title><link rel="stylesheet" href="style.css" type="text/css"/></head>
<body><h1>{html.escape(title)}</h1>{body}</body></html>'''


def block_html(block: Block, chinese: str) -> str:
    cls = {"center": "setting", "stage": "stage", "dialogue": "dialogue"}.get(block.kind, "text")
    zh = "<br/>".join(html.escape(x) for x in chinese.splitlines())
    it = "<br/>".join(html.escape(x) for x in block.text.splitlines())
    return (
        f'<section class="block {cls}"><div class="zh">{zh}</div>'
        f'<details><summary>義大利文原文</summary><div class="it" lang="it">{it}</div></details></section>'
    )


def build_chapters(all_blocks: list[tuple[str, list[Block]]], cache: dict[str, str]):
    chapters: list[tuple[str, str, str]] = []
    for section_title, blocks in all_blocks:
        if section_title == "角色介紹":
            body = []
            for block in blocks:
                body.append(block_html(block, translate(block.text, cache)))
            chapters.append(("characters.xhtml", "角色介紹", "".join(body)))
            continue
        act_no = "1" if section_title == "第一幕" else "2"
        scene_no = 0
        current_title = f"{section_title}・開場"
        current: list[str] = []
        for block in blocks:
            found = scene_title(block.text) if block.kind == "center" else None
            if found:
                if current:
                    chapters.append((f"act{act_no}-scene{scene_no:02}.xhtml", current_title, "".join(current)))
                scene_no += 1
                current_title = f"{section_title}・{found}"
                current = []
            current.append(block_html(block, translate(block.text, cache)))
        if current:
            chapters.append((f"act{act_no}-scene{scene_no:02}.xhtml", current_title, "".join(current)))
    return chapters


STYLE = '''
body { font-family: serif; line-height: 1.75; margin: 6%; color: #222; }
h1 { text-align: center; margin: 1.5em 0; }
h2 { margin-top: 1.5em; }
.block { margin: 1.1em 0; }
.setting { text-align: center; }
.stage { color: #555; font-style: italic; padding-left: 1em; border-left: 0.2em solid #bbb; }
.dialogue { margin: 1.1em 0; }
.zh { white-space: normal; }
details { margin-top: 0.35em; color: #666; font-size: 0.88em; }
summary { cursor: pointer; }
.it { margin-top: 0.4em; padding-left: 0.8em; border-left: 0.15em solid #ddd; }
.notice { padding: 1em; background: #f2f2f2; }
nav ol { line-height: 1.8; }
'''


def build_epub(chapters: list[tuple[str, str, str]]) -> None:
    OUT.parent.mkdir(parents=True, exist_ok=True)
    book_id = f"urn:uuid:{uuid.uuid4()}"
    title_body = '''
<p class="setting">沃夫岡・阿瑪迪斯・莫札特 作曲</p>
<p class="setting">洛倫佐・達・龐特 劇本</p>
<p class="setting">繁體中文初譯／義大利文對照</p>
<div class="notice"><p>本書供個人閱讀與研究使用。義大利文原作為公版，底本取自義大利文維基文庫所收錄的 1867 年版本。</p>
<p>中文為機器初譯並統一角色譯名，尚非正式出版譯本；詩韻、雙關語與歌唱重音請以義大利文原文為準。</p></div>
'''
    pages = [("title.xhtml", "唐・喬凡尼", title_body)] + chapters
    nav_items = "".join(
        f'<li><a href="{html.escape(name)}">{html.escape(title)}</a></li>' for name, title, _ in pages
    )
    nav = xhtml_page("目錄", f'<nav epub:type="toc" xmlns:epub="http://www.idpf.org/2007/ops"><ol>{nav_items}</ol></nav>')
    manifest_pages = "".join(
        f'<item id="p{i}" href="{name}" media-type="application/xhtml+xml"/>'
        for i, (name, _, _) in enumerate(pages)
    )
    spine = "".join(f'<itemref idref="p{i}"/>' for i in range(len(pages)))
    ncx_points = "".join(
        f'<navPoint id="n{i}" playOrder="{i+1}"><navLabel><text>{html.escape(title)}</text></navLabel><content src="{name}"/></navPoint>'
        for i, (name, title, _) in enumerate(pages)
    )
    opf = f'''<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid" xml:lang="zh-Hant">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="bookid">{book_id}</dc:identifier>
<dc:title>唐・喬凡尼：繁體中文義大利文對照劇本</dc:title><dc:creator>Wolfgang Amadeus Mozart</dc:creator>
<dc:creator>Lorenzo Da Ponte</dc:creator><dc:language>zh-Hant</dc:language><dc:language>it</dc:language>
<dc:rights>Italian source text: public domain. Chinese draft prepared for personal study.</dc:rights>
<meta property="dcterms:modified">2026-10-20T14:30:00Z</meta></metadata>
<manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
<item id="css" href="style.css" media-type="text/css"/><item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>{manifest_pages}</manifest>
<spine toc="ncx">{spine}</spine></package>'''
    ncx = f'''<?xml version="1.0" encoding="utf-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1"><head><meta name="dtb:uid" content="{book_id}"/></head>
<docTitle><text>唐・喬凡尼</text></docTitle><navMap>{ncx_points}</navMap></ncx>'''
    container = '''<?xml version="1.0" encoding="utf-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles>
<rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>'''
    with zipfile.ZipFile(OUT, "w") as zf:
        zf.writestr("mimetype", "application/epub+zip", compress_type=zipfile.ZIP_STORED)
        zf.writestr("META-INF/container.xml", container)
        zf.writestr("OEBPS/style.css", STYLE)
        zf.writestr("OEBPS/nav.xhtml", nav)
        zf.writestr("OEBPS/content.opf", opf)
        zf.writestr("OEBPS/toc.ncx", ncx)
        for name, title, body in pages:
            zf.writestr(f"OEBPS/{name}", xhtml_page(title, body))


def validate_epub() -> None:
    with zipfile.ZipFile(OUT) as zf:
        names = set(zf.namelist())
        assert zf.namelist()[0] == "mimetype"
        assert zf.read("mimetype") == b"application/epub+zip"
        assert "META-INF/container.xml" in names
        assert "OEBPS/content.opf" in names
        assert "OEBPS/nav.xhtml" in names
        for name in names:
            if name.endswith(".xhtml"):
                data = zf.read(name).decode("utf-8")
                assert "<html" in data and "</html>" in data


def main() -> None:
    cache = load_cache()
    all_blocks: list[tuple[str, list[Block]]] = []
    for title, page in SOURCE_PAGES:
        parser = WikisourceParser()
        parser.feed(fetch_rendered(page))
        blocks = normalize_source(parser.blocks)
        if not blocks:
            raise RuntimeError(f"No content extracted from {page}")
        all_blocks.append((title, blocks))
        print(f"{title}: {len(blocks)} blocks")
    chapters = build_chapters(all_blocks, cache)
    build_epub(chapters)
    validate_epub()
    print(f"chapters={len(chapters)} cache={len(cache)} output={OUT} size={OUT.stat().st_size}")


if __name__ == "__main__":
    main()
