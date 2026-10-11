---
ingested: 2026-10-10
sha256: d920ced21c99a1aa6b5bdb9bb541bfd223eb1ab0f1e6d30bebf1174a12261ba3
---

# Owner statements on task status rules, 2026-10-10

This note records what the repository owner stated on 2026-10-10 about how the `task_*` family treats a task's text and its `status`. The statements were made in a working session whose transcript is a local file outside the repository, so they are excerpted below verbatim as the authoritative copy. No machine path or session id is given.

## Statements

The owner wrote this after an audit loop on a change to the family's status rules:

> Archiving (is that the same as "finish") should NOT change the content of a task; its content should always only change before implementation. The changes after ready are only implemented, audited, finished, or deferred. In all cases, the content of a task does not change, only its state. The whole idea of "hey, look, there are multiple links to the same doc" is "hey, the task might be poorly written, double-check if it is organically grown, and therefore, doing so many links, and maybe the sections should be reorganized"

The owner then refined the archiving point and stated when a rewrite earns a re-check:

> Yes, rewriting is part of archiving, but that is mechanical rewriting and must NEVER change the status of a task (beyond going from audited to finished or from whatever to deferred)! And a task that was implemented is never marked as checked. and archived tasks (finished or deferred) must never change status once they have earned that status, even if their content in the archive is rewritten. The concept of changing the status only makes sense BEFORE implementation, as it is to recheck the task that was rewritten before implementation. And also, a mechanical change to links is not a reason for re-check; adding an acceptance criterion might not even be enough - it depends on how much that is of a change, while adjusting the goal is always a reason. (as long as the task was not implemented)

The owner asked for a wiki record so that agents can compare the family against these rules:

> you should create a page in the repos wiki explaining how the task system works (is supposed to work) so an agent could see when it diverges in implementation or when checking or in test from the supposed ways of working

The first version of that page restated two points the owner had not put in these words. One was the size test: an Approach or Acceptance change needs a re-check when it asks for work or a check the task did not already require. The other was the routing rule: gaps that a re-audit finds in audited or archived work go to a new follow-up task. The owner confirmed both:

> yes that follows my intention

An earlier statement, recorded in the repository's task backlog before this session, draws the same line for completed work. The owner had a repair to an implemented task reverted, stating that implemented work is either left alone or was never implemented.

## Context

The statements answered a change that sent every rewrite of a `ready` task outside the linter's mechanical fix set back to `checked`, regroups and additive notes included, and that made the readiness loop run a second readiness check after a link regroup. The owner rejected that trigger and asked for the family to follow the statements above.
