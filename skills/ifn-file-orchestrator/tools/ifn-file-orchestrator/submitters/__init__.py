"""IFN-side submitters — the ONLY modules in this codebase that mutate
IFN state. Triage / parsers / builders are pure functions over file
content; submitters wrap the `ifn` CLI commands that propose vouchers
and write file metadata. Keeping side-effects isolated here makes
"don't accidentally hit IFN" a structural property rather than a
flag-checking ritual.

Convention: each submitter exposes one function that takes well-shaped
inputs and returns a structured `{status, error?, response_summary?, …}`
dict. The orchestrator decides WHETHER to call them; the submitters
don't gate themselves.
"""
