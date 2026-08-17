Releases are now produced by CI rather than by hand. Every merge to main is
published automatically, with the next version derived from the highest published
tag instead of from catalog.json, so a stale or conflicted catalog can no longer
roll the version of record backwards. Contributors add a release-note fragment and
an optional release:minor / release:major label; nobody edits the catalog. The
promote-release button now tags and publishes inside its own run, fixing a
long-standing bug where promotions bumped the catalog to a version that was never
tagged and never moved the rolling stable or beta tag.
