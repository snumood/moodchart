/* Patient-only consent UI. The server rechecks role, approval and hospital on every RPC. */
async function openJournalShare() {
  const dialog = document.getElementById('journal-share-dialog');
  dialog.showModal();
  await loadJournalShare();
}

async function loadJournalShare() {
  const list = document.getElementById('journal-share-list');
  const select = document.getElementById('journal-share-doctor');
  const msg = document.getElementById('journal-share-msg');
  const grant = document.getElementById('journal-share-grant');
  list.replaceChildren(); select.replaceChildren(); grant.disabled = true;
  msg.textContent = I18N.t('목록을 불러오는 중입니다.');
  try {
    const [consents, doctors] = await Promise.all([
      sb.rpc('journal_list_share_consents'), sb.rpc('journal_list_share_doctors')
    ]);
    if (consents.error) throw new Error('share');
    for (const c of consents.data || []) {
      const row = document.createElement('li');
      const name = document.createElement('span');
      name.textContent = `${c.doctor_name || '-'} / ${c.hospital_name || '-'} · ${String(c.granted_at).slice(0, 10)} `;
      row.append(name);
      if (!c.eligible) {
        const note = document.createElement('span'); note.textContent = I18N.t('현재 열람 불가'); row.append(note);
      }
      const revoke = document.createElement('button');
      revoke.type = 'button'; revoke.textContent = I18N.t('공유 철회');
      revoke.addEventListener('click', () => changeJournalShare('journal_revoke_share', c.doctor_id, revoke));
      row.append(revoke); list.append(row);
    }
    if (!list.children.length) {
      const empty = document.createElement('li'); empty.textContent = I18N.t('공유 중인 의료진이 없습니다.'); list.append(empty);
    }
    if (doctors.error && doctors.error.code !== '22023') throw new Error('share');
    if (doctors.error) {
      msg.textContent = I18N.t('계정에서 병원코드와 환자번호를 먼저 연결해 주세요.'); return;
    }
    for (const d of doctors.data || []) {
      const option = document.createElement('option'); option.value = d.doctor_id;
      option.textContent = `${d.doctor_name || '-'} / ${d.hospital_name || '-'} (${d.hospital_code})`; select.append(option);
    }
    grant.disabled = !select.options.length;
    msg.textContent = select.options.length ? '' : I18N.t('선택할 수 있는 승인된 의료진이 없습니다.');
  } catch {
    msg.textContent = I18N.t('공유 정보를 불러오지 못했습니다. 다시 시도해 주세요.');
  }
}

async function changeJournalShare(rpc, doctorId, button) {
  if (!doctorId || button.disabled) return;
  const granting = rpc === 'journal_grant_share';
  if (!confirm(I18N.t(granting ? '선택한 의료진에게 기분기록을 공유할까요?' : '이 의료진의 기분기록 공유를 철회할까요?'))) return;
  button.disabled = true;
  try {
    const { error } = await sb.rpc(rpc, { p_doctor: doctorId });
    if (error) throw new Error('share');
    await loadJournalShare();
    document.getElementById('journal-share-msg').textContent = I18N.t(granting ? '기록 공유를 시작했습니다.' : '기록 공유를 철회했습니다.');
  } catch {
    document.getElementById('journal-share-msg').textContent = I18N.t('공유 설정을 바꾸지 못했습니다. 다시 시도해 주세요.');
  } finally { button.disabled = button.id === 'journal-share-grant' && !document.getElementById('journal-share-doctor').options.length; }
}

document.getElementById('journal-share-grant').addEventListener('click', event =>
  changeJournalShare('journal_grant_share', document.getElementById('journal-share-doctor').value, event.currentTarget));
