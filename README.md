# Q10 – Scholarship Application Assessment (schema `q10`)

**Purpose:** approve applicants who are aged 18–25 inclusive, with monthly income ≤ K3,000 and average mark ≥ 70.

## Objects
| Part | Object | What it does |
|---|---|---|
| (a) | `students`, `applications`, `decision_audit` | CHECKs: age > 0, income ≥ 0, mark 0–100, status PENDING/APPROVED/REJECTED; 6 PENDING applications incl. boundary cases (18/3000/70, 25/3000/70, 26, 3001, 69.99) |
| (b) | `fn_scholarship_eligible(age, income, mark)` | boolean result; rejects NULL and invalid values |
| (c) | `pr_assess_application(id)` | requires an existing PENDING application; sets APPROVED or REJECTED; clear errors otherwise |
| (d) | `trg_applications_decision_audit` | AFTER UPDATE, only when `status` actually changes |
| (e) | `v_approved_applicants` | student number, name, mark, status; APPROVED only, income omitted |
| (f) | `idx_applications_status_submitted (status, submitted_on)` | status equality + date range |
| (g) | `pr_assess_pending()` + job `q10_assess_pending` | query FOR loop over PENDING rows; cron `0 8 * * 1` |

## Expected results
Three APPROVED (rows 1–3) and three REJECTED (rows 4–6). A second run of `pr_assess_pending()` changes nothing, and `decision_audit` keeps exactly 6 rows.
