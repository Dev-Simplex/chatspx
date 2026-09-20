-- Run read-only with a tenant-bound role, replacing :account_id. No cross-tenant dashboard by default.
-- Publication is the denominator. Pre-sanitizer and pre-TTS are diagnostic, never added to it.
WITH publications AS (
  SELECT account_id, captain_assistant_id, publication_path, fact_type, publication_id,
         min(created_at) AS observed_at,
         bool_or(decision = 'would_block') AS violation,
         bool_or(decision = 'would_allow') AS supported,
         bool_or(decision = 'unassessed') AS unassessed
  FROM captain_fact_guard_events
  WHERE account_id = :account_id AND stage = 'publication'
    AND created_at >= now() - interval '14 days'
  GROUP BY 1,2,3,4,5
)
SELECT account_id, captain_assistant_id, publication_path, fact_type,
       count(*) AS observed_publications,
       count(*) FILTER (WHERE violation) AS would_block,
       count(*) FILTER (WHERE supported AND NOT violation) AS supported,
       count(*) FILTER (WHERE unassessed) AS unassessed,
       round(100.0 * count(*) FILTER (WHERE violation) /
         nullif(count(*) FILTER (WHERE violation OR supported), 0), 2) AS violation_pct_assessed,
       min(observed_at) AS first_in_window
FROM publications GROUP BY 1,2,3,4 ORDER BY 1,2,3,4;

-- Readiness = at least 14 elapsed days PER dimension, not automatic permission to arm.
SELECT account_id, captain_assistant_id, publication_path,
       min(created_at) AS first_seen, max(created_at) AS last_seen,
       count(DISTINCT created_at::date) AS measured_days,
       now() - min(created_at) >= interval '14 days' AS minimum_elapsed,
       count(*) FILTER (WHERE reason = 'ledger_unavailable') AS ledger_failures
FROM captain_fact_guard_events WHERE account_id = :account_id AND stage = 'publication'
GROUP BY 1,2,3;

-- Disagreements introduced/fixed by the sanitizer. Inspect claims + evidence_ids in the private DB.
SELECT publication_id, fact_type,
       bool_or(decision = 'would_block') FILTER (WHERE stage = 'pre_sanitizer') AS raw_block,
       bool_or(decision = 'would_block') FILTER (WHERE stage = 'publication') AS final_block
FROM captain_fact_guard_events WHERE account_id = :account_id
GROUP BY 1,2 HAVING count(DISTINCT stage) > 1;

-- Complete-source storage growth and judge-only latency (end-to-end latency is in independent telemetry).
SELECT origin, count(*) AS results, sum(pg_column_size(full_result)) AS stored_bytes,
       avg(octet_length(full_result::text)) AS mean_uncompressed_bytes
FROM captain_evidence_sources WHERE account_id = :account_id
GROUP BY origin;
SELECT publication_path, percentile_cont(0.95) WITHIN GROUP (ORDER BY duration_ms) AS judge_p95_ms
FROM captain_fact_guard_events WHERE account_id = :account_id
GROUP BY publication_path;

-- Mandatory independent log/metrics query during DB outages:
-- event="captain.fact_guard.shadow" AND reason IN
-- ("ledger_unavailable", "scope_unavailable", "publication_observer_unavailable")
-- group by account_id,captain_assistant_id,publication_path; count.
-- The SQL denominator alone cannot see an unavailable database or uninstrumented producers.
