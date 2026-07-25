# Error Ledger -- 23 enumerated LLM errors, frozen for attack replay

Citation integrity: 1 paraphrase-as-verbatim (ARIES/Meyer/Merkle);
2 fabricated quote completion (G004); 3 quote/label mismatch (G004b);
4 restructured quote (P001); 5 false "already verified" (POSIX URLs);
6 verifier built but not run before shipping.
Shipped rule violations: 7 2>/dev/null in printed instructions;
8 space-indented .gd despite tabs note; 9 bare gdshrapt/gdcli invocations;
10 undercounted soft issues; 11 sed -n used while gating sed.
Verification failures: 12 memory-written anchor (spacing); 13 self-tripping
detector; 14 wfile.write false positive; 15 monotonic rate-limit bug;
16 backslash escaping in nested heredoc; 17 missing citations in one
deliverable; 18 dismissed guided-settings requirement; 19 never ran bare
invocation.
Fabricated environment claims: 20 invented UI menu path; 21 invented
allowlist entry; 22 confident wrong prediction pre-test.
Procedural: 23 malformed tool calls (missing required fields).
Cross-LLM: false files_to_fix status='fixed' row with unchanged file sha.
