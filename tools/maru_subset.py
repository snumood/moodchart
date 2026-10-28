"""MaruBuri 를 세 사이트에 맞게 나눔: core = 세 사이트 글에 쓰인 글자, ext = 나머지 상용 한글 2,350자(KS X 1001).
브라우저는 unicode-range 로 필요한 파일만 받으므로, 평소엔 core 만 받고 새 글자가 생기면 ext 로 채워짐."""
import sys, re, subprocess
from pathlib import Path
from fontTools.ttLib import TTFont
SRC, OUT = Path(sys.argv[1]), Path(sys.argv[2]); OUT.mkdir(parents=True, exist_ok=True)
W = Path('/Users/hongisu/Documents/ChatGPT/Full paper/work')
roots = [W/'homepage-20261028/homepage-v2', W/'mssi-en-20261028/MSSI', W/'moodchart-design-20261028/moodchart']
txt = []
for r in roots:
    for p in r.rglob('*'):
        if p.suffix not in {'.html', '.js', '.css', '.svg', '.json', '.ts', '.tsx'} or not p.is_file(): continue
        if any(x in p.parts for x in ('.git', 'node_modules', 'backups', 'vendor', 'vendor-build')): continue
        txt.append(p.read_text(encoding='utf-8', errors='ignore'))
used = set(''.join(txt))
cm = TTFont(SRC/'MaruBuri-Regular.woff2').getBestCmap()
ks = set()
for cp in range(0xAC00, 0xD7A4):
    try:
        if len(chr(cp).encode('euc-kr')) == 2: ks.add(cp)
    except UnicodeEncodeError: pass
base = set(range(0x20, 0x7F)) | {0xA0, 0xB7, 0x2013, 0x2014, 0x2018, 0x2019, 0x201C, 0x201D, 0x2026, 0x00B7, 0x3001, 0x3002, 0x300C, 0x300D}
core = sorted((set(map(ord, used)) | base) & set(cm))
ext = sorted((ks - set(core)) & set(cm))
def ranges(cps):
    out, s = [], None
    for i, c in enumerate(cps):
        if s is None: s = p = c
        elif c == p + 1: p = c
        else: out.append((s, p)); s = p = c
        if i == len(cps) - 1: out.append((s, p))
    return ', '.join(f'U+{a:X}' if a == b else f'U+{a:X}-{b:X}' for a, b in out)
css = ['/* MaruBuri (© NAVER Corp., SIL Open Font License 1.1).',
       '   core: 세 사이트 글에 쓰인 글자 / ext: 나머지 상용 한글. 필요한 파일만 받음. 다시 만들기: maru_subset.py */']
for w, name in [(300, 'Light'), (400, 'Regular'), (600, 'SemiBold')]:
    for part, cps in [('core', core), ('ext', ext)]:
        f = OUT/f'maruburi-{name.lower()}-{part}.woff2'
        subprocess.run([sys.executable, '-m', 'fontTools.subset', str(SRC/f'MaruBuri-{name}.woff2'), f'--unicodes={",".join(f"{c:X}" for c in cps)}',
                        '--flavor=woff2', '--layout-features=*', f'--output-file={f}'], check=True)
        css.append(f"@font-face {{\n  font-family: 'MaruBuri';\n  font-style: normal;\n  font-weight: {w};\n  font-display: swap;\n  src: url(./maruburi/{f.name}) format('woff2');\n  unicode-range: {ranges(cps)};\n}}")
(OUT/'maruburi.css').write_text('\n'.join(css) + '\n', encoding='utf-8')
print('core', len(core), 'ext', len(ext), 'hangul used', sum(1 for c in used if '가' <= c <= '힣'), 'hangul used not in font', ''.join(sorted(c for c in used if '가' <= c <= '힣' and ord(c) not in cm)))
