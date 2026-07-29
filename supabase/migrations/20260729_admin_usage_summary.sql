-- Aggregate-only usage statistics for the Google OAuth moodchart administrator.
-- This migration adds no tables, triggers, tracking, or writes to patient data.

CREATE OR REPLACE FUNCTION public.moodchart_admin_usage_summary(
    p_period TEXT DEFAULT '4w'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_period TEXT := lower(trim(COALESCE(p_period, '4w')));
    v_start_date DATE;
    v_end_date DATE := (now() AT TIME ZONE 'Asia/Seoul')::DATE;
    v_period_label TEXT;
    v_result JSONB;
BEGIN
    IF NOT public.is_moodchart_admin() THEN
        RAISE EXCEPTION 'Admin authorization required' USING ERRCODE = '42501';
    END IF;

    CASE v_period
        WHEN '1w' THEN
            v_start_date := v_end_date - 6;
            v_period_label := '최근 1주';
        WHEN '2w' THEN
            v_start_date := v_end_date - 13;
            v_period_label := '최근 2주';
        WHEN '4w' THEN
            v_start_date := v_end_date - 27;
            v_period_label := '최근 4주';
        WHEN '2m' THEN
            v_start_date := (v_end_date - INTERVAL '2 months')::DATE;
            v_period_label := '최근 2개월';
        WHEN '3m' THEN
            v_start_date := (v_end_date - INTERVAL '3 months')::DATE;
            v_period_label := '최근 3개월';
        WHEN '6m' THEN
            v_start_date := (v_end_date - INTERVAL '6 months')::DATE;
            v_period_label := '최근 6개월';
        WHEN '1y' THEN
            v_start_date := (v_end_date - INTERVAL '1 year')::DATE;
            v_period_label := '최근 1년';
        ELSE
            RAISE EXCEPTION 'Invalid statistics period' USING ERRCODE = '22023';
    END CASE;

    WITH valid_records AS (
        SELECT r.username, r.record_date
        FROM public.records AS r
        INNER JOIN public.users AS u ON u.username = r.username
        WHERE r.category <> 'dummy'
          AND NULLIF(btrim(COALESCE(r.value, '')), '') IS NOT NULL
    ),
    period_records AS (
        SELECT vr.username, vr.record_date
        FROM valid_records AS vr
        WHERE vr.record_date BETWEEN v_start_date AND v_end_date
    ),
    active_users AS (
        SELECT DISTINCT pr.username
        FROM period_records AS pr
    ),
    first_records AS (
        SELECT vr.username, min(vr.record_date) AS first_record_date
        FROM valid_records AS vr
        GROUP BY vr.username
    ),
    record_days AS (
        SELECT DISTINCT pr.username, pr.record_date
        FROM period_records AS pr
    ),
    usage_stats AS (
        SELECT
            (SELECT count(*)::INTEGER FROM active_users) AS active_users,
            (
                SELECT count(*)::INTEGER
                FROM active_users AS au
                INNER JOIN public.users AS u ON u.username = au.username
                WHERE NULLIF(btrim(COALESCE(u.hospital_id, '')), '') IS NOT NULL
            ) AS linked_users,
            (
                SELECT count(*)::INTEGER
                FROM active_users AS au
                INNER JOIN public.users AS u ON u.username = au.username
                WHERE NULLIF(btrim(COALESCE(u.hospital_id, '')), '') IS NULL
            ) AS unlinked_users,
            (
                SELECT count(*)::INTEGER
                FROM first_records AS fr
                WHERE fr.first_record_date BETWEEN v_start_date AND v_end_date
            ) AS new_record_users,
            (SELECT count(*)::INTEGER FROM record_days) AS record_days
    ),
    current_inventory AS (
        SELECT i.username, i.sender_username, COALESCE(i.source, '') AS source
        FROM public.inventory AS i
        INNER JOIN public.users AS owner_user ON owner_user.username = i.username
    ),
    gift_rows AS (
        SELECT ci.username, ci.sender_username, ci.source
        FROM current_inventory AS ci
        WHERE ci.source LIKE 'gift%'
          AND NULLIF(btrim(COALESCE(ci.sender_username, '')), '') IS NOT NULL
    ),
    gift_senders AS (
        SELECT DISTINCT gr.sender_username AS username
        FROM gift_rows AS gr
        INNER JOIN public.users AS sender_user ON sender_user.username = gr.sender_username
    ),
    gift_receivers AS (
        SELECT DISTINCT gr.username
        FROM gift_rows AS gr
    ),
    gift_participants AS (
        SELECT gs.username FROM gift_senders AS gs
        UNION
        SELECT gr.username FROM gift_receivers AS gr
    ),
    inventory_stats AS (
        SELECT
            (SELECT count(DISTINCT ci.username)::INTEGER FROM current_inventory AS ci) AS item_holders,
            (SELECT count(*)::INTEGER FROM current_inventory) AS current_items,
            (SELECT count(*)::INTEGER FROM gift_rows) AS gift_transfers,
            (SELECT count(*)::INTEGER FROM gift_senders) AS gift_senders,
            (SELECT count(*)::INTEGER FROM gift_receivers) AS gift_receivers,
            (SELECT count(*)::INTEGER FROM gift_participants) AS gift_participants,
            (
                SELECT count(*)::INTEGER
                FROM gift_rows AS gr
                WHERE gr.source NOT LIKE 'gift_reply%'
            ) AS normal_gifts,
            (
                SELECT count(*)::INTEGER
                FROM gift_rows AS gr
                WHERE gr.source LIKE 'gift_reply%'
            ) AS reply_gifts
    )
    SELECT jsonb_build_object(
        'period', v_period,
        'period_label', v_period_label,
        'period_start', v_start_date,
        'period_end', v_end_date,
        'active_users', us.active_users,
        'linked_users', us.linked_users,
        'unlinked_users', us.unlinked_users,
        'new_record_users', us.new_record_users,
        'record_days', us.record_days,
        'average_record_days',
            CASE
                WHEN us.active_users = 0 THEN 0
                ELSE round(us.record_days::NUMERIC / us.active_users, 1)
            END,
        'item_holders', ist.item_holders,
        'current_items', ist.current_items,
        'gift_transfers', ist.gift_transfers,
        'gift_senders', ist.gift_senders,
        'gift_receivers', ist.gift_receivers,
        'gift_participants', ist.gift_participants,
        'normal_gifts', ist.normal_gifts,
        'reply_gifts', ist.reply_gifts
    )
    INTO v_result
    FROM usage_stats AS us
    CROSS JOIN inventory_stats AS ist;

    RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.moodchart_admin_usage_summary(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.moodchart_admin_usage_summary(TEXT) TO authenticated;
