"use strict";

/* ================================================================
   STEP 01：画面切り替え（ホーム / クイズ）
================================================================ */
const pages = {
  home: document.getElementById("home-page"),
  quiz: document.getElementById("quiz-page")
};
const navigation = document.querySelectorAll("[data-page]");

function showPage(name) {
  if (!pages[name]) return;
  Object.entries(pages).forEach(([key, element]) => { element.hidden = key !== name; });
  navigation.forEach(button => {
    const isCurrent = button.dataset.page === name;
    button.classList.toggle("active", isCurrent);
    if (isCurrent) button.setAttribute("aria-current", "page");
    else button.removeAttribute("aria-current");
  });
  window.scrollTo({top: 0, behavior: "auto"});
}

navigation.forEach(button => button.addEventListener("click", () => showPage(button.dataset.page)));
document.getElementById("home-logo").addEventListener("click", event => {
  event.preventDefault(); showPage("home");
});

/* ================================================================
   STEP 02：発音の処理
   左：教育部のWAVをHTMLAudioElementで再生
   右：ブラウザのSpeechSynthesis APIで中国語の例単語を読む
================================================================ */
const audioMessage = document.getElementById("audio-message");
let currentAudio = null;

function stopPreviousSounds() {
  if (currentAudio) { currentAudio.pause(); currentAudio.currentTime = 0; currentAudio = null; }
  if ("speechSynthesis" in window) window.speechSynthesis.cancel();
}

function playSymbol(item) {
  stopPreviousSounds();
  const sound = new Audio(`audio/${item.audio}`);
  currentAudio = sound;
  audioMessage.textContent = `「${item.symbol}」の発音を再生中`;
  sound.addEventListener("ended", () => { if (currentAudio === sound) audioMessage.textContent = ""; });
  sound.addEventListener("error", () => { audioMessage.textContent = `音声が開けません：audio/${item.audio}`; });
  sound.play().catch(() => { audioMessage.textContent = "音声を再生できません。WAVファイルを確認してください。"; });
}

function speakWord(item) {
  stopPreviousSounds();
  if (!("speechSynthesis" in window)) {
    audioMessage.textContent = "このブラウザは音声合成に対応していません。";
    return;
  }
  const speech = new SpeechSynthesisUtterance(item.word);
  speech.lang = "zh-TW";
  speech.rate = 0.85;
  const voices = window.speechSynthesis.getVoices();
  const taiwanVoice = voices.find(v => v.lang.toLowerCase().replace("_", "-") === "zh-tw");
  if (taiwanVoice) speech.voice = taiwanVoice;
  audioMessage.textContent = `「${item.word}」を読み上げ中（中国語音声が必要です）`;
  speech.onend = () => { audioMessage.textContent = ""; };
  speech.onerror = () => { audioMessage.textContent = "音声合成に失敗しました。OSの中国語音声を確認してください。"; };
  window.speechSynthesis.speak(speech);
}

/* ================================================================
   STEP 03：37個のカードを作成
   innerHTMLを使わず、テキストを安全に挿入する。
================================================================ */
function makeTextElement(tag, className, text) {
  const node = document.createElement(tag);
  node.className = className;
  node.textContent = text;
  return node;
}

function createSymbolCard(item) {
  const card = document.createElement("article");
  card.className = "symbol-card";

  const symbolButton = document.createElement("button");
  symbolButton.type = "button";
  symbolButton.className = "sound-button";
  symbolButton.setAttribute("aria-label", `${item.symbol}の注音発音を聞く`);
  symbolButton.append(
    makeTextElement("span", "symbol-char", item.symbol),
    makeTextElement("span", "kana", item.kana)
  );
  symbolButton.addEventListener("click", () => playSymbol(item));

  const wordButton = document.createElement("button");
  wordButton.type = "button";
  wordButton.className = "word-button";
  wordButton.setAttribute("aria-label", `${item.word}（${item.wordZhuyin}）の中国語読み上げ`);
  wordButton.append(
    makeTextElement("span", "word-text", item.word),
    makeTextElement("span", "word-zhuyin", item.wordZhuyin),
    makeTextElement("span", "word-kana", `近似音：${item.wordKana}`),
    makeTextElement("span", "word-meaning", `意味：${item.meaning}`),
    makeTextElement("span", "play-hint", "▶ 発音")
  );
  wordButton.addEventListener("click", () => speakWord(item));

  card.append(symbolButton, wordButton);
  return card;
}

function renderSymbolTable() {
  const container = document.getElementById("symbol-groups");
  container.replaceChildren();
  GROUP_TITLES.forEach(group => {
    const section = document.createElement("section");
    section.className = "symbol-section";
    const title = makeTextElement("h2", "section-title", group.label);
    const description = makeTextElement("p", "section-description", group.description);
    const grid = document.createElement("div");
    grid.className = "card-grid";
    SYMBOLS.filter(item => item.group === group.id).forEach(item => grid.appendChild(createSymbolCard(item)));
    section.append(title, description, grid);
    container.appendChild(section);
  });
}

/* ================================================================
   STEP 04：クイズの問題作成
   1）37文字をランダムに並べる → 最初の10件を使用
   2）同じ種類を優先して3つの不正解候補を選ぶ
   3）選択肢も毎回シャッフルする
================================================================ */
const TOTAL_QUESTIONS = 10;
let quizQuestions = [];
let questionIndex = 0;
let score = 0;
let hasAnswered = false;

function shuffle(array) {
  const copy = [...array];
  for (let i = copy.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [copy[i], copy[j]] = [copy[j], copy[i]];
  }
  return copy;
}

function makeChoices(correct) {
  const sameGroup = shuffle(SYMBOLS.filter(item => item !== correct && item.group === correct.group));
  const otherGroup = shuffle(SYMBOLS.filter(item => item !== correct && item.group !== correct.group));
  return shuffle([correct, ...sameGroup.concat(otherGroup).slice(0, 3)]);
}

/* ================================================================
   STEP 05：クイズの開始・一問ずつ表示
================================================================ */
const quizStart = document.getElementById("quiz-start");
const quizQuestion = document.getElementById("quiz-question");
const quizResult = document.getElementById("quiz-result");
const answerList = document.getElementById("answer-list");
const answerFeedback = document.getElementById("answer-feedback");
const nextButton = document.getElementById("next-button");

function startQuiz() {
  quizQuestions = shuffle(SYMBOLS).slice(0, TOTAL_QUESTIONS);
  questionIndex = 0;
  score = 0;
  quizStart.hidden = true;
  quizResult.hidden = true;
  quizQuestion.hidden = false;
  renderQuestion();
}

function renderQuestion() {
  hasAnswered = false;
  const correct = quizQuestions[questionIndex];
  document.getElementById("quiz-progress").textContent = `問題 ${questionIndex + 1} / ${TOTAL_QUESTIONS}`;
  document.getElementById("quiz-score").textContent = `正解 ${score}`;
  document.getElementById("question-symbol").textContent = correct.symbol;
  answerFeedback.textContent = "";
  nextButton.hidden = true;
  answerList.replaceChildren();

  makeChoices(correct).forEach(choice => {
    const option = document.createElement("button");
    option.type = "button";
    option.className = "answer-button";
    option.textContent = choice.kana;
    option.addEventListener("click", () => selectAnswer(choice, correct, option));
    answerList.appendChild(option);
  });
}

/* ================================================================
   STEP 06：正解判定・点数計算・結果の表示
================================================================ */
function selectAnswer(choice, correct, selectedButton) {
  if (hasAnswered) return;
  hasAnswered = true;
  const isCorrect = choice.symbol === correct.symbol;
  if (isCorrect) score++;

  answerList.querySelectorAll("button").forEach(button => {
    button.disabled = true;
    if (button.textContent === correct.kana) button.classList.add("correct");
  });
  if (!isCorrect) selectedButton.classList.add("wrong");
  answerFeedback.textContent = isCorrect
    ? `正解！「${correct.symbol}」は「${correct.kana}」に近い音です。`
    : `不正解。正解は「${correct.kana}」です。`;
  document.getElementById("quiz-score").textContent = `正解 ${score}`;
  nextButton.hidden = false;
  nextButton.textContent = questionIndex === TOTAL_QUESTIONS - 1 ? "結果を見る" : "次の問題へ";
}

function showQuizResult() {
  quizQuestion.hidden = true;
  quizResult.hidden = false;
  document.getElementById("result-score").textContent = `${score} / ${TOTAL_QUESTIONS}`;
  document.getElementById("result-text").textContent = `正答率 ${Math.round(100 * score / TOTAL_QUESTIONS)}％ ／ お疲れさまでした！`;
}

nextButton.addEventListener("click", () => {
  if (!hasAnswered) return;
  questionIndex++;
  if (questionIndex === TOTAL_QUESTIONS) showQuizResult();
  else renderQuestion();
});
document.getElementById("start-button").addEventListener("click", startQuiz);
document.getElementById("restart-button").addEventListener("click", startQuiz);

/* ================================================================
   STEP 07：初期処理
   URLを開いたら必ず注音符号表を先に表示する。
================================================================ */
renderSymbolTable();
showPage("home");