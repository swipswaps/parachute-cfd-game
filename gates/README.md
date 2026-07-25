Gates -- Executable Enforcement of the Working Rules
====================================================

This repository converts every LLM error observed in the parachute-cfd-game
session (23 enumerated, docs/error_ledger.md) into code that REFUSES, not
prose that promises. Each gate is importable, self-tested, and replayed
against the original error as an attack in tests/test_gates.py.

-------------------------------------------------------------------------------
TABLE OF CONTENTS
-------------------------------------------------------------------------------

1.  Overview
2.  Error -> Gate Map
3.  File-by-File Technical Reference
4.  Run Instructions
5.  FAQ / Troubleshooting
6.  Glossary
7.  Verbatim Citations
8.  References

-------------------------------------------------------------------------------
1. OVERVIEW
-------------------------------------------------------------------------------

Two different LLMs (Claude, DeepSeek) produced the same failure classes in
one session: fabricated citations, false "fixed" database records, edits
anchored on guessed text, success claims without execution, and suppressed
output. Every class recurred despite written rules. Conclusion: rules that
live in prose are advisory; rules that live in code are enforced. This
repository is the code.

-------------------------------------------------------------------------------
2. ERROR -> GATE MAP
-------------------------------------------------------------------------------

Errors #1-6   (fabricated/paraphrased citations, verifier not run)
              -> gates/citation_gate.py
Errors #7,11  (2>/dev/null in instructions; sed inconsistency)
              -> gates/output_gate.py
Errors #8-10  (style/invocation/undercount shipped)     -> gates/delivery_gate.py
Errors #12,16 (memory-anchored edits, escaping)         -> gates/guarded_edit.py
Errors #13-15,17-19,22 (shipped without adversarial run)-> gates/delivery_gate.py
Errors #20,21 (fabricated environment claims)           -> gates/claim_gate.py
Error  #23    (malformed tool calls)                    -> gates/claim_gate.py
False 'fixed' DB rows (both LLMs)                       -> gates/fix_record_gate.py

-------------------------------------------------------------------------------
3. FILE-BY-FILE TECHNICAL REFERENCE
-------------------------------------------------------------------------------

3.1 gates/guarded_edit.py

Design by Contract applied to text editing: an edit's anchor must match the
file content exactly once, the write is read back, and a verifier command
must exit 0, or the edit reports failure and (where possible) restores.

CS Principle: precondition/postcondition with fail-hard semantics.

Verbatim citation (retrieved earlier this conversation):
"DbC's 'fail hard' property simplifies the debugging of contract behavior
as the intended behaviour of each routine is clearly specified."
Source: en.wikipedia.org/wiki/Design_by_contract

3.2 gates/citation_gate.py

Validates a citations catalogue: every entry must EITHER carry evidence of
in-session retrieval (verbatim_evidence naming an HTTP 200 fetch) OR an
explicit pending status. An entry claiming verification without evidence
fields fails the gate. This makes error #2 (fabricated quote stamped
VERIFIED) structurally unshippable.

3.3 gates/output_gate.py

Scans shell scripts, Python sources, AND echo/print instruction strings for
2>/dev/null, bare sed mutation, and set -e. Instruction strings matter
because printed commands cross the trust boundary when pasted (error #7).

Verbatim citation (retrieved earlier this conversation):
"By default, Bash continues executing a script even when a command fails."
Source: linuxize.com/post/bash-exit/

3.4 gates/fix_record_gate.py

Installs SQLite BEFORE INSERT/UPDATE triggers on files_to_fix so that
status='fixed' structurally requires pre_sha256 != post_sha256 AND
verifier_exit = 0. Replayed against the real false record
('Duplicate var dir removed', file sha unchanged 76bc469f...) in tests.

3.5 gates/claim_gate.py

Claims about the environment must be constructed from a probe that actually
ran. make_claim() refuses to emit an assertion without an attached evidence
dict containing the command, returncode, and output. Prevents errors #20/#21
(invented UI path, invented allowlist entry).

3.6 gates/delivery_gate.py

Pre-delivery checklist runner: syntax gates (bash -n / py_compile / ast),
bare-invocation smoke test (argv=[]), and a self-scan via output_gate.
PASS is only emitted from recorded execution results -- there is no code
path that prints PASS from a claim.

3.7 tests/test_gates.py

Replays each historical error as an attack and asserts the gate rejects it,
plus the legitimate path is accepted. Run via scripts/run_all_gates.sh.

3.8 scripts/run_all_gates.sh

Self-hosting runner: compiles every module, runs the attack tests, then
runs output_gate against this repository's own files. Exit 0 only if all
recorded results pass.

3.9 docs/error_ledger.md

The 23 enumerated errors with their evidence, frozen as the reference the
tests replay.

-------------------------------------------------------------------------------
4. RUN INSTRUCTIONS
-------------------------------------------------------------------------------

    cd gates
    bash scripts/run_all_gates.sh

Exit 0 = every gate compiled, every attack replay rejected, legitimate
paths accepted, and this repository passes its own output gate.

To install the database trigger gate on the live pipeline DB:

    python3 -c "from gates.fix_record_gate import install; install('../parachute_mutations.db')"

-------------------------------------------------------------------------------
5. FAQ / TROUBLESHOOTING
-------------------------------------------------------------------------------

Q: A gate rejected my legitimate edit.
A: Read the reason string -- it names the violated precondition (match
   count, read-back mismatch, or verifier exit). Fix the input, not the gate.

Q: Can I bypass a gate in an emergency?
A: The file gates: yes, by not calling them -- they gate the honest path.
   The DB trigger: no; that is the point. Drop the trigger explicitly (and
   loudly) if you truly must, then reinstall.

Q: Why does citation_gate accept 'pending' entries?
A: Honesty about non-verification is compliant; CLAIMING verification
   without evidence is the violation.

-------------------------------------------------------------------------------
6. GLOSSARY
-------------------------------------------------------------------------------

Anchor -- exact text an edit locates; must match exactly once.
Attack replay -- re-running a historical error's inputs against a gate.
Evidence dict -- {cmd, returncode, stdout, stderr} from a real execution.
Gate -- code that refuses an operation whose preconditions fail.
Read-after-write -- re-reading written content before trusting the write.

-------------------------------------------------------------------------------
7. VERBATIM CITATIONS
-------------------------------------------------------------------------------

Retrieved by real fetch earlier in this conversation (HTTP 200, quoted from
returned bodies or the user's own rules file which embeds them):

- Design by Contract: "DbC's 'fail hard' property simplifies the debugging
  of contract behavior as the intended behaviour of each routine is clearly
  specified." -- en.wikipedia.org/wiki/Design_by_contract
- Bash exit semantics: "By default, Bash continues executing a script even
  when a command fails." -- linuxize.com/post/bash-exit/
- Read-after-write: "Read-after-Write Consistency: Makes sure that if a
  write is accepted, the next read will include that write."
  -- geeksforgeeks.org/system-design/strong-vs-eventual-consistency-in-system-design/
- Toil: "Toil is the kind of work that tends to be manual, repetitive,
  automatable, tactical, devoid of enduring value..." -- SRE Book ch. 5,
  quoted at cloud.google.com (identifying-and-tracking-toil)

NOT verified in this session (marked honestly, per the same standard as
citations_catalogue.json P003/P006/P007 -- egress proxy returned 403):

- POSIX grep/awk pages at pubs.opengroup.org [UNVERIFIED THIS SESSION]

-------------------------------------------------------------------------------
8. REFERENCES
-------------------------------------------------------------------------------

- docs/error_ledger.md (this repository)
- ../citations_catalogue.json (verification provenance schema)
- ../multi_tool_audit.db (gate run history)
- Home Assistant recorder corruption recovery: raw.githubusercontent.com
  /home-assistant/core/dev/homeassistant/components/recorder/util.py
  (fetched HTTP 200 earlier this conversation)
- rqlite integrity/backup: rqlite/rqlite db/db.go (fetched HTTP 200)
- Litestream checkpoint tiers: benbjohnson/litestream db.go (fetched HTTP 200)
