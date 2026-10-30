/* Patient-only consent UI: one switch per clinician. The server rechecks role, approval and hospital on every RPC. */
async function openJournalShare() {
  const dialog = document.getElementById('journal-share-dialog');
  dialog.showModal();
  await loadJournalShare();
}

function journalShareRow(list, doctor, on) {
  const row = document.createElement('li');
  const text = document.createElement('span');
  text.textContent = `${doctor.doctor_name || '-'} / ${doctor.hospital_name || '-'}`;
  if (on && doctor.granted_at) {
    const since = document.createElement('small');
    since.textContent = ` · ${String(doctor.granted_at).slice(0, 10)}~`;
    text.append(since);
  }
  if (doctor.eligible === false) {
    const note = document.createElement('small');
    note.textContent = ` · ${I18N.t('현재 열람 불가')}`;
    text.append(note);
  }
  const sw = document.createElement('label');
  sw.className = 'share-switch';
  const input = document.createElement('input');
  input.type = 'checkbox'; input.setAttribute('role', 'switch'); input.checked = on;
  input.dataset.doctor = doctor.doctor_id;
  input.setAttribute('aria-label', `${doctor.doctor_name || '-'}: ${I18N.t(on ? '공유 중' : '공유 안 함')}`);
  input.addEventListener('change', () => changeJournalShare(input));
  sw.append(input, document.createElement('span'));
  row.append(text, sw);
  list.append(row);
}

async function loadJournalShare() {
  const list = document.getElementById('journal-share-list');
  const msg = document.getElementById('journal-share-msg');
  const link = document.getElementById('journal-share-link');
  list.replaceChildren(); link.hidden = true;
  msg.textContent = I18N.t('목록을 불러오는 중입니다.');
  try {
    const [consents, doctors] = await Promise.all([
      sb.rpc('journal_list_share_consents'), sb.rpc('journal_list_share_doctors')
    ]);
    if (consents.error) throw new Error('share');
    if (doctors.error && doctors.error.code !== '22023') throw new Error('share');
    const active = new Map((consents.data || []).map(c => [c.doctor_id, c]));
    // Same-hospital approved clinicians, then any older consent that is still active (so it can be switched off).
    for (const d of doctors.data || []) journalShareRow(list, { ...d, ...(active.get(d.doctor_id) || {}) }, active.has(d.doctor_id));
    const listed = new Set((doctors.data || []).map(d => d.doctor_id));
    for (const c of consents.data || []) if (!listed.has(c.doctor_id)) journalShareRow(list, c, true);
    if (doctors.error) { link.hidden = false; msg.textContent = I18N.t('계정에서 병원코드와 환자번호를 먼저 연결해 주세요.'); return; }
    msg.textContent = list.children.length ? '' : I18N.t('같은 병원에 승인된 의료진이 없습니다.');
  } catch {
    msg.textContent = I18N.t('공유 정보를 불러오지 못했습니다. 다시 시도해 주세요.');
  }
}

async function changeJournalShare(input) {
  const granting = input.checked;
  if (!confirm(I18N.t(granting ? '선택한 의료진에게 기분기록을 공유할까요?' : '이 의료진의 기분기록 공유를 철회할까요?'))) {
    input.checked = !granting; return;
  }
  const msg = document.getElementById('journal-share-msg');
  document.querySelectorAll('#journal-share-list input').forEach(i => { i.disabled = true; });
  try {
    const { error } = await sb.rpc(granting ? 'journal_grant_share' : 'journal_revoke_share', { p_doctor: input.dataset.doctor });
    if (error) throw new Error('share');
    await loadJournalShare();
    msg.textContent = I18N.t(granting ? '기록 공유를 시작했습니다.' : '기록 공유를 철회했습니다.');
  } catch {
    // Show the server's actual state rather than the switch position the user tried.
    await loadJournalShare();
    msg.textContent = I18N.t('공유 설정을 바꾸지 못했습니다. 다시 시도해 주세요.');
  }
}
