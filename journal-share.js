/* Patient-only consent UI: one switch. On = share with the approved clinician(s) of the patient's hospital
   (one hospital, one doctor for now); off = revoke every active share. The server rechecks role, approval
   and hospital on every RPC. */
async function openJournalShare() {
  document.getElementById('journal-share-dialog').showModal();
  await loadJournalShare();
}

let journalShareDoctors = [], journalShareActive = [];

async function loadJournalShare() {
  const sw = document.getElementById('journal-share-switch');
  const msg = document.getElementById('journal-share-msg');
  const link = document.getElementById('journal-share-link');
  sw.disabled = true; link.hidden = true;
  msg.textContent = I18N.t('목록을 불러오는 중입니다.');
  try {
    const [consents, doctors] = await Promise.all([
      sb.rpc('journal_list_share_consents'), sb.rpc('journal_list_share_doctors')
    ]);
    if (consents.error) throw new Error('share');
    if (doctors.error && doctors.error.code !== '22023') throw new Error('share');
    journalShareActive = (consents.data || []).map(c => c.doctor_id);
    journalShareDoctors = doctors.error ? [] : (doctors.data || []).map(d => d.doctor_id);
    sw.checked = journalShareActive.length > 0;
    // Switching off must stay possible even when no clinician can be selected any more.
    sw.disabled = !sw.checked && !journalShareDoctors.length;
    if (doctors.error && !sw.checked) { link.hidden = false; msg.textContent = I18N.t('계정에서 병원코드와 환자번호를 먼저 연결해 주세요.'); return; }
    if (!sw.checked && !journalShareDoctors.length) { msg.textContent = I18N.t('같은 병원에 승인된 의료진이 없습니다.'); return; }
    msg.textContent = I18N.t(sw.checked ? '기록을 공유하고 있어요.' : '기록을 공유하지 않고 있어요.');
  } catch {
    msg.textContent = I18N.t('공유 정보를 불러오지 못했습니다. 다시 시도해 주세요.');
  }
}

async function changeJournalShare() {
  const sw = document.getElementById('journal-share-switch');
  const granting = sw.checked;
  if (!confirm(I18N.t(granting ? '담당 의료진에게 기분기록을 공유할까요?' : '기분기록 공유를 멈출까요?'))) {
    sw.checked = !granting; return;
  }
  const msg = document.getElementById('journal-share-msg');
  sw.disabled = true;
  try {
    const targets = granting ? journalShareDoctors : journalShareActive;
    for (const doctor of targets) {
      const { error } = await sb.rpc(granting ? 'journal_grant_share' : 'journal_revoke_share', { p_doctor: doctor });
      if (error) throw new Error('share');
    }
    await loadJournalShare();
    msg.textContent = I18N.t(granting ? '기록 공유를 시작했습니다.' : '기록 공유를 철회했습니다.');
  } catch {
    // Show the server's actual state rather than the switch position the user tried.
    await loadJournalShare();
    msg.textContent = I18N.t('공유 설정을 바꾸지 못했습니다. 다시 시도해 주세요.');
  }
}

document.getElementById('journal-share-switch').addEventListener('change', changeJournalShare);
