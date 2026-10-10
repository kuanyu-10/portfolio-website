"use strict";

/* ================================================================
   STEP 01：37個の注音符号データ（並び順は教育部の基本順序）
   symbol：注音文字
   kana：日本語で近い音（近似であり、厳密な発音ではない）
   word ：中国語の例単語（右側を押すと読み上げ）
   wordZhuyin：例単語の注音表記（声調を含む）
   wordKana：例単語の日本語カタカナ近似音（声調は再現できない）
   meaning：日本語訳
   audio：教育部の音声ファイル名（F1.WAV ～ F37.WAV）
   ※ カタカナは学習時の補助表記。正確な発音はWAVで確認する。
================================================================ */
const SYMBOLS = [
  {symbol:"ㄅ", kana:"ポ（息を抑える）", word:"包子", wordZhuyin:"ㄅㄠ ˙ㄗ", wordKana:"パオズ", meaning:"肉まん", audio:"F1.WAV", group:"initial"},
  {symbol:"ㄆ", kana:"ポ（強く息を出す）", word:"葡萄", wordZhuyin:"ㄆㄨˊ ㄊㄠˊ", wordKana:"プータオ", meaning:"ぶどう", audio:"F2.WAV", group:"initial"},
  {symbol:"ㄇ", kana:"モ", word:"媽媽", wordZhuyin:"ㄇㄚ ˙ㄇㄚ", wordKana:"マーマ", meaning:"お母さん", audio:"F3.WAV", group:"initial"},
  {symbol:"ㄈ", kana:"フォ", word:"飛機", wordZhuyin:"ㄈㄟ ㄐㄧ", wordKana:"フェイジー", meaning:"飛行機", audio:"F4.WAV", group:"initial"},
  {symbol:"ㄉ", kana:"トゥ（息を抑える）", word:"大象", wordZhuyin:"ㄉㄚˋ ㄒㄧㄤˋ", wordKana:"ダーシャン", meaning:"ゾウ", audio:"F5.WAV", group:"initial"},
  {symbol:"ㄊ", kana:"トゥ（強く息を出す）", word:"太陽", wordZhuyin:"ㄊㄞˋ ㄧㄤˊ", wordKana:"タイヤン", meaning:"太陽", audio:"F6.WAV", group:"initial"},
  {symbol:"ㄋ", kana:"ヌ", word:"牛奶", wordZhuyin:"ㄋㄧㄡˊ ㄋㄞˇ", wordKana:"ニウナイ", meaning:"牛乳", audio:"F7.WAV", group:"initial"},
  {symbol:"ㄌ", kana:"ル", word:"老師", wordZhuyin:"ㄌㄠˇ ㄕ", wordKana:"ラオシー", meaning:"先生", audio:"F8.WAV", group:"initial"},
  {symbol:"ㄍ", kana:"ク（息を抑える）", word:"哥哥", wordZhuyin:"ㄍㄜ ˙ㄍㄜ", wordKana:"グーグー", meaning:"お兄さん", audio:"F9.WAV", group:"initial"},
  {symbol:"ㄎ", kana:"ク（強く息を出す）", word:"咖啡", wordZhuyin:"ㄎㄚ ㄈㄟ", wordKana:"カーフェイ", meaning:"コーヒー", audio:"F10.WAV", group:"initial"},
  {symbol:"ㄏ", kana:"ホ（のどの奥）", word:"花", wordZhuyin:"ㄏㄨㄚ", wordKana:"ホワ", meaning:"花", audio:"F11.WAV", group:"initial"},
  {symbol:"ㄐ", kana:"チ（舌を前・弱い息）", word:"雞蛋", wordZhuyin:"ㄐㄧ ㄉㄢˋ", wordKana:"ジーダン", meaning:"卵", audio:"F12.WAV", group:"initial"},
  {symbol:"ㄑ", kana:"チ（舌を前・強い息）", word:"氣球", wordZhuyin:"ㄑㄧˋ ㄑㄧㄡˊ", wordKana:"チーチウ", meaning:"風船", audio:"F13.WAV", group:"initial"},
  {symbol:"ㄒ", kana:"シ（舌を前に）", word:"西瓜", wordZhuyin:"ㄒㄧ ㄍㄨㄚ", wordKana:"シーグワ", meaning:"スイカ", audio:"F14.WAV", group:"initial"},
  {symbol:"ㄓ", kana:"チ（舌を巻く・弱い息）", word:"知道", wordZhuyin:"ㄓ ㄉㄠˋ", wordKana:"ジーダオ", meaning:"知っている", audio:"F15.WAV", group:"initial"},
  {symbol:"ㄔ", kana:"チ（舌を巻く・強い息）", word:"吃飯", wordZhuyin:"ㄔ ㄈㄢˋ", wordKana:"チーファン", meaning:"ご飯を食べる", audio:"F16.WAV", group:"initial"},
  {symbol:"ㄕ", kana:"シ（舌を巻く）", word:"獅子", wordZhuyin:"ㄕ ˙ㄗ", wordKana:"シーズ", meaning:"ライオン", audio:"F17.WAV", group:"initial"},
  {symbol:"ㄖ", kana:"リ（舌を巻く）", word:"日子", wordZhuyin:"ㄖˋ ˙ㄗ", wordKana:"リーズ", meaning:"日々", audio:"F18.WAV", group:"initial"},
  {symbol:"ㄗ", kana:"ツ（息を抑える）", word:"字母", wordZhuyin:"ㄗˋ ㄇㄨˇ", wordKana:"ズームー", meaning:"文字", audio:"F19.WAV", group:"initial"},
  {symbol:"ㄘ", kana:"ツ（強く息を出す）", word:"草莓", wordZhuyin:"ㄘㄠˇ ㄇㄟˊ", wordKana:"ツァオメイ", meaning:"いちご", audio:"F20.WAV", group:"initial"},
  {symbol:"ㄙ", kana:"ス", word:"四季", wordZhuyin:"ㄙˋ ㄐㄧˋ", wordKana:"スージー", meaning:"四季", audio:"F21.WAV", group:"initial"},
  {symbol:"ㄚ", kana:"ア", word:"阿姨", wordZhuyin:"ㄚ ㄧˊ", wordKana:"アーイー", meaning:"おばさん", audio:"F22.WAV", group:"final"},
  {symbol:"ㄛ", kana:"オ（口を丸く）", word:"波浪", wordZhuyin:"ㄅㄛ ㄌㄤˋ", wordKana:"ボーラン", meaning:"波", audio:"F23.WAV", group:"final"},
  {symbol:"ㄜ", kana:"ウ（口を横に）", word:"鵝", wordZhuyin:"ㄜˊ", wordKana:"ウー", meaning:"ガチョウ", audio:"F24.WAV", group:"final"},
  {symbol:"ㄝ", kana:"エ（口を広げる）", word:"夜晚", wordZhuyin:"ㄧㄝˋ ㄨㄢˇ", wordKana:"イエワン", meaning:"夜", audio:"F25.WAV", group:"final"},
  {symbol:"ㄞ", kana:"アイ", word:"愛心", wordZhuyin:"ㄞˋ ㄒㄧㄣ", wordKana:"アイシン", meaning:"思いやり", audio:"F26.WAV", group:"final"},
  {symbol:"ㄟ", kana:"エイ", word:"杯子", wordZhuyin:"ㄅㄟ ˙ㄗ", wordKana:"ベイズ", meaning:"コップ", audio:"F27.WAV", group:"final"},
  {symbol:"ㄠ", kana:"アオ", word:"高興", wordZhuyin:"ㄍㄠ ㄒㄧㄥˋ", wordKana:"ガオシン", meaning:"うれしい", audio:"F28.WAV", group:"final"},
  {symbol:"ㄡ", kana:"オウ", word:"歐洲", wordZhuyin:"ㄡ ㄓㄡ", wordKana:"オウジョウ", meaning:"ヨーロッパ", audio:"F29.WAV", group:"final"},
  {symbol:"ㄢ", kana:"アン（nで止める）", word:"安全", wordZhuyin:"ㄢ ㄑㄩㄢˊ", wordKana:"アンチュエン", meaning:"安全", audio:"F30.WAV", group:"final"},
  {symbol:"ㄣ", kana:"エン（nで止める）", word:"恩人", wordZhuyin:"ㄣ ㄖㄣˊ", wordKana:"エンレン", meaning:"恩人", audio:"F31.WAV", group:"final"},
  {symbol:"ㄤ", kana:"アン（ngで止める）", word:"昂貴", wordZhuyin:"ㄤˊ ㄍㄨㄟˋ", wordKana:"アングイ", meaning:"高価", audio:"F32.WAV", group:"final"},
  {symbol:"ㄥ", kana:"オン（ngで止める）", word:"風", wordZhuyin:"ㄈㄥ", wordKana:"フォン", meaning:"風", audio:"F33.WAV", group:"final"},
  {symbol:"ㄦ", kana:"アール（巻き舌）", word:"耳朵", wordZhuyin:"ㄦˇ ˙ㄉㄨㄛ", wordKana:"アルドゥオ", meaning:"耳", audio:"F34.WAV", group:"final"},
  {symbol:"ㄧ", kana:"イ", word:"衣服", wordZhuyin:"ㄧ ˙ㄈㄨ", wordKana:"イーフー", meaning:"服", audio:"F35.WAV", group:"medial"},
  {symbol:"ㄨ", kana:"ウ", word:"烏龜", wordZhuyin:"ㄨ ㄍㄨㄟ", wordKana:"ウーグイ", meaning:"カメ", audio:"F36.WAV", group:"medial"},
  {symbol:"ㄩ", kana:"ユ（唇を丸く）", word:"魚", wordZhuyin:"ㄩˊ", wordKana:"ユー", meaning:"魚", audio:"F37.WAV", group:"medial"}
];

/* ================================================================
   STEP 02：分類の説明（日本語）
   語学初心者に伝わるよう、専門用語と短い説明を両方表示する。
================================================================ */
const GROUP_TITLES = [
  {id:"initial", label:"声母（21文字）", description:"音節の最初に置く子音です。例：ㄅ・ㄆ・ㄇ。"},
  {id:"final", label:"韻母（13文字）", description:"音節の中心や終わりを作る音です。例：ㄚ・ㄞ・ㄢ。"},
  {id:"medial", label:"介音（3文字）", description:"音節の中で使う ㄧ・ㄨ・ㄩ の3文字です。これだけで音節になる場合もあります。"}
];