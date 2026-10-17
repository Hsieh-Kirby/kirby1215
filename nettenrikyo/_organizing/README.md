# nettenrikyo 舊站整理區

這個資料夾只用來整理舊站內容，目前不會匯入 `kirby1215.tw`，也不會搬動或改寫原始 HTML、圖片與文件。

## 第一階段分類

| 代碼 | 分類 | 對應舊站內容 | 整理原則 |
|---|---|---|---|
| 01 | 三原典 | `triple/`、`triple.html` | 御筆先、神樂歌、御指圖及相關譯註分開保留 |
| 02 | 教理與教義 | `teaching/`、`teaching.html` | 教典、逸話篇、主題教理與研究文章分層 |
| 03 | 講演與神殿講話 | `speech.html` 及缺少的 `speech/` | 依年份、場合、講者整理；目前正文來源缺失 |
| 04 | 文章與翻譯 | `article/`、`article.html` | 再分心得、翻譯、人物／系列、歷史文章 |
| 05 | 個人札記與系列 | `window/`、`happy/` | 版主小窗與未在主選單中的系列先集中辨識 |
| 06 | 學習資源 | `resource.html`、`files/` | 下載文件與外部連結分開 |
| 90 | 舊版與備份 | `old design/`、檔名含 `old` | 只存檔，不列為正式內容 |
| 91 | 共用素材 | 根目錄 `images/` | 圖片待確認使用頁面後再歸屬 |

## 目前盤點

- 共 1,061 個原始檔案：439 個 HTML、551 個 JPG、30 個 PNG、1 個 GIF、37 個 PDF、2 個 PPTX、1 個 DOCX。
- 最大內容群是 `article/`，共 626 個檔案，其中 246 個 HTML。
- `speech/` 已包含 56 篇演講稿正文，文章列表已擷取篇名與講者。
- 舊頁面含失效相對連結、Windows `file:///D|/...` 絕對路徑，以及多層頁面錯指首頁等問題。
- `article-old.html`、`old design/` 及若干 `*(old).html` 應視為版本備份，不宜和正式內容混列。

## 建議的下一步

1. 先在 `content-inventory.csv` 逐項確認 `category`，尤其是 `article/chi*`、`happy/` 和 `window/`。
2. 為 56 篇演講稿補上年份、場合與講者等結構化欄位。
3. 確認分類後，再建立一份全新的整理副本；舊站原檔繼續作為唯讀來源。
4. 最後才決定哪些內容要進入 `kirby1215.tw`，以及網址、標籤和作者欄位如何對應。

## 清冊更新

從專案根目錄執行：

```powershell
powershell -ExecutionPolicy Bypass -File tools/catalog-nettenrikyo.ps1
```

清冊使用英文欄名，以相容舊版 Windows PowerShell；分類中文名稱請對照上表。`status` 和 `notes` 欄可人工補充；重新產生清冊會覆蓋它們，因此完成人工標註後不要直接重跑。

## 文章列表

- `分類文章列表.md`：全部分類的可閱讀總表。
- `article-list.csv`：方便日後匯入或用試算表調整的資料表。
- `lists/`：三原典、教理、演講稿、文章與翻譯、個人札記、學習資源各自一份列表。
- `匯入決策.md`：站主已確認的保留、排除及待審核範圍；正式轉換以此為準。

重新產生文章列表：

```powershell
node tools/build-nettenrikyo-article-lists.mjs
```
