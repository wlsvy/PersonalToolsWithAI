// 페이지(각 프레임)에 주입된다. vendor의 Readability, TurndownService가 먼저 주입돼 있어야 한다.
// 다시 주입돼도 재선언 에러가 없도록 최상위에는 function 선언만 둔다.
function extractMarkdown() {
  // Readability가 넘겨받은 DOM을 직접 고치므로 복제본에서 작업
  const doc = document.cloneNode(true);

  // lazy-load: src는 빈 gif 같은 자리표시자, 실제 주소는 data-* 에 있는 경우
  for (const img of doc.querySelectorAll('img')) {
    const real = img.dataset.src || img.dataset.lazySrc || img.dataset.original;
    if (real) img.setAttribute('src', real);
  }

  // Readability 휴리스틱이 놓치는 광고만 좁게 지운다. [class*="ad"]처럼 넓히면 header/shadow까지 지워진다.
  doc.querySelectorAll(
    'iframe, ins.adsbygoogle, [id^="google_ads"], [id^="div-gpt-ad"], [class*="sponsor"], [class*="advert"]'
  ).forEach((el) => el.remove());

  const article = new Readability(doc).parse();
  if (!article) return '';

  const td = new TurndownService({ headingStyle: 'atx', codeBlockStyle: 'fenced' });
  return `# ${article.title}\n\n${td.turndown(article.content)}`;
}
