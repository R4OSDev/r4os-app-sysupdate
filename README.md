# SYSUPD.R4X

`SYSUPD.R4X` is an independent R4OS application implemented in Zig.

## Package

- Version: `0.1.18`
- Image target: `/R4OS/SOFTWARE/TERMINAL/SYSUPD.R4X`
- Image scope: `slim`
- Canonical project manifest: `module.R4MF`

The manifest is the single source of truth for the artifact, imports, image
target, and package metadata.

## Build

On Windows:

    Build.bat

On Linux or macOS:

    ./Build.sh

The build starters resolve the current local R4OS dependency checkouts through
`Settings.R4S`. The URL and hash entries in `build.zig.zon` record the
last verified standalone dependency identities; workspace builds use the
mapped local checkouts.

## Documentation

Live apply verifies payloads while staging. Restart commit verifies all
private stages before replacing active files. Terminal output includes the
actual payload stream attempts and bytes read, including retries. Metadata
reads use bounded blocks; recovery and source-binding checks remain shared
with the service engine.

Version 0.1.17 provisions missing parents of admitted C: payload targets when
staging under the existing durable update intent. Verification checks parent
types without creating directories. A file in the ancestor chain is a conflict;
creation is checked by a fresh lookup and uses the existing bounded I/O retry.
Abort/rollback retains shared directories while removing only identity-bound
payload/stage files. The journal format and internal boot-volume path are
unchanged. UPDSVC uses this same implementation.

Detailed German technical notes from the migration are preserved in
`DOCUMENTATION.de.txt`. Source-transfer provenance is recorded in
`PROVENANCE.txt`.

`SYSUPD ARCHIVE-BOOT-BACKUP Bxxxxxxx.R4U` moves one unreferenced boot backup
into `C:\R4OS\UPDATE\ARCHIVE`. Under the update lease, both journal slots,
boot configuration and sibling FAT identities must exclude the candidate.
The original name is removed only after durable copying, full byte comparison
and a second reference check. Foreign archive contents are retained and
reported as a failure. This explicit maintenance command does not rewrite
the journal, discard backup contents or repair a damaged filesystem.

## License

Original R4OS material is licensed under Apache License 2.0. See `LICENSE`
and `NOTICE`. Any repository-specific external material is documented in
`THIRD_PARTY_NOTICES.md`.

Graphics packages and last-good restore (0.1.18)
----------------------------------------------
License and corresponding-source companions are admitted only below
C:\R4OS\LICENSES and C:\R4OS\SOURCES and require an already active Kernel
0.1.199 or newer. A queued kernel cannot satisfy this requirement. Batch
dependency checks include the final installed provider, including downgrades.

SYSUPD ROLLBACK-LAST checks the latest transaction's complete targets and
fingerprinted backups, persists rollback intent and reboots. The normal
early boot recovery restores files before driver activation. This is an
explicit return to the pre-update set, not an automatic GPU-health verdict.
It accepts completed or pending-post-boot transactions; stale/changed files,
missing backups and competing batches stop before publishing rollback intent.
After a batch restore, RESUME-BATCH reconciles the batch state. If the kernel
was restored too, boot again to run that restored kernel. Recovery remains
the independent repair route when the installed kernel cannot start.
