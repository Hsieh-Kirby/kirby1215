import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
cache_path = root / "output" / "don-giovanni-translation-cache.json"
missing_path = root / "output" / "don-giovanni-missing.json"
cache = json.loads(cache_path.read_text(encoding="utf-8"))
missing = json.loads(missing_path.read_text(encoding="utf-8"))

translations = [
    """喬凡尼：我的心意已決，毫不畏懼，我會去。
騎士長：把手給我，作為憑證。
喬凡尼：給你……哎呀！……
騎士長：你怎麼了？
喬凡尼：這是何等的冰冷！
騎士長：悔改吧，改變你的生活；這是最後的時刻。
喬凡尼：不，不，我絕不悔改……
（想掙脫，卻徒勞無功。）
離我遠一點。
騎士長：悔改吧，惡徒。
喬凡尼：不，你這昏聵的老頭。
騎士長：悔改吧。
喬凡尼：不。
騎士長、雷波雷洛：是。
喬凡尼：不。
騎士長：啊！已經沒有時間了。
（火焰從四面升起；騎士長消失，地面裂開一道深淵。）
喬凡尼：一陣異常的顫慄……我感到……群鬼向我襲來！……
那些火焰的旋渦從何而來……哎呀，多麼恐怖！……
合唱：對你的罪行而言，這一切還遠遠不夠！（地下傳來聲音）
來吧，還有更可怕的懲罰。
喬凡尼：是誰撕裂我的靈魂！……
是誰翻攪我的五臟！……
多麼痛苦！哎呀，多麼煎熬！
這是何等的地獄！何等恐怖……
雷波雷洛：（他那絕望的面容！……
那受詛咒般的動作！……
那些叫喊！那些哀號！
真把我嚇壞了！……）
合唱：對你的罪行而言，這一切還遠遠不夠：
來吧！還有更可怕的懲罰。
（火勢增強，眾復仇女神現身，抓住喬凡尼，將他一同拖入地底。）""",
    "終場",
    "艾維拉、安娜、采琳娜、奧塔維奧公爵和馬賽托進場；雷波雷洛驚魂未定。",
    """眾人（安娜與雷波雷洛除外）：
啊！那惡徒在哪裡？
那卑鄙的人在哪裡？
我要把滿腔怒火全都發洩出來。
安娜：唯有看見他身陷枷鎖，才能平息我的痛苦。
雷波雷洛：別再指望找到他……
別再找了……
他已去了很遠的地方。
眾人：怎麼回事？快說，別再拖延！""",
    """雷波雷洛：來了一個巨人……可是我實在說不清……
在濃煙與烈火之中……請仔細聽……
那個石頭人……先停一下……
就在那下面……發出一聲巨響！……
就在那裡，魔鬼把他整個吞了下去。
眾人：天啊，我聽到了什麼！
雷波雷洛：事情千真萬確。
眾人：那一定就是我遇見的幽靈。
奧塔維奧：如今，我的珍寶，
上天已替我們所有人報了仇；
請給我一點安慰吧，
不要再讓我苦苦等待。
安娜：親愛的，再給我一年，
讓我盡情宣洩心中的哀痛。
忠貞的愛終將回應
愛慕你之人的心願。
艾維拉：我要進修道院，
在那裡度過餘生。
采琳娜、馬賽托：我們——采琳娜和馬賽托——回家去，
一同享用晚餐。
雷波雷洛：我則要去客棧，
另找一位更好的主人。
采琳娜、馬賽托、雷波雷洛：就讓那個惡棍
跟冥后普羅塞庇娜和冥王普魯托待在一起吧。
善良的人們，讓我們大家
歡歡喜喜地重唱
這首古老的歌謠：
眾人：這就是作惡之人的下場！
奸邪之人的死亡，
永遠與他的一生相稱。""",
    "——全劇終——",
]

if len(missing) != len(translations):
    raise RuntimeError(f"Expected {len(translations)} missing passages, found {len(missing)}")

for source, translated in zip(missing, translations):
    cache[source] = translated

cache_path.write_text(json.dumps(cache, ensure_ascii=False, indent=2), encoding="utf-8")
print(f"Added {len(translations)} translations; cache now has {len(cache)} entries")
