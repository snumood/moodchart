// K-BSDS: O/X 19문항(1점씩) + 마지막 문항(6·4·2·0점)을 더해 0–25점과 해석을 보여 줌. 응답은 어디에도 저장하지 않음.
(function () {
    const TEXT = {
        ko: {
            partial: (n, s) => `${n}/20 문항에 답했어요 · 지금까지 ${s}점`,
            none: '문항에 O·X를 고르면 점수가 여기에 나와요.',
            score: s => `${s}점`,
            bands: ['양극성장애 가능성이 매우 낮음', '양극성장애 가능성이 낮음', '양극성장애 가능성이 있음', '양극성장애 가능성이 매우 높음'],
            ranges: ['6점 이하', '7–12점', '13–19점', '20점 이상'],
            note: '간단한 설문이라 의사의 진단을 대신할 수 없어요. 결과가 걱정되면 진료 때 담당 의사와 상의해 보세요. 응답은 저장되지 않습니다.',
            reset: '다시 하기'
        },
        en: {
            partial: (n, s) => `${n} of 20 answered · ${s} so far`,
            none: 'Choose O or X for each statement and your score appears here.',
            score: s => `${s} points`,
            bands: ['Possibility of bipolar disorder: very low', 'Possibility of bipolar disorder: low', 'Possibility of bipolar disorder: present', 'Possibility of bipolar disorder: very high'],
            ranges: ['6 or less', '7–12', '13–19', '20 or more'],
            note: 'A simple questionnaire cannot replace a doctor’s diagnosis. If the result worries you, talk it over with your doctor at your next visit. Your answers are not saved.',
            reset: 'Start over'
        }
    };
    const band = s => s <= 6 ? 0 : s <= 12 ? 1 : s <= 19 ? 2 : 3;
    function wire(root) {
        root.querySelectorAll('.kbsds').forEach(box => {
            if (box.dataset.wired) return;
            box.dataset.wired = '1';
            const t = TEXT[box.dataset.lang] || TEXT.ko;
            const out = box.querySelector('.kb-result');
            if (!out) return;
            const update = () => {
                let sum = 0, n = 0;
                for (let k = 1; k <= 20; k++) {
                    const c = box.querySelector(`input[name="kb${k}"]:checked`);
                    if (c) { sum += Number(c.value); n++; }
                }
                out.classList.toggle('done', n === 20);
                box.querySelector('.kb-reset').hidden = !n;
                if (!n) { out.innerHTML = `<p class="kb-msg">${t.none}</p>`; return; }
                if (n < 20) { out.innerHTML = `<p class="kb-msg">${t.partial(n, sum)}</p>`; return; }
                const b = band(sum);
                out.innerHTML = `<div class="kb-score">${t.score(sum)}</div>`
                    + `<div class="kb-band b${b}">${t.bands[b]}</div>`
                    + `<div class="kb-scale" aria-hidden="true">${t.ranges.map((r, i) => `<span class="${i === b ? 'on' : ''}">${r}</span>`).join('')}<i style="left:${(sum / 25) * 100}%"></i></div>`
                    + `<p class="kb-note">${t.note}</p>`;
            };
            box.addEventListener('change', update);
            const reset = box.querySelector('.kb-reset');
            reset.textContent = t.reset;
            reset.addEventListener('click', () => { box.querySelectorAll('input:checked').forEach(i => { i.checked = false; }); update(); box.querySelector('input')?.focus(); });
            update();
        });
    }
    window.wireKbsds = wire;
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', () => wire(document));
    else wire(document);
})();
