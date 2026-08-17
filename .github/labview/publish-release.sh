#!/usr/bin/env bash
# Publish the version currently in the catalog: immutable tag, moving aliases,
# rolling channel tags, GitHub Release.
#
# This used to live inline in release.yml, which meant it only ever ran when a
# push to main touched catalog.json. Pushes made with the built-in GITHUB_TOKEN
# do not trigger workflows, so every catalog bump written by promote-release.yml
# was announced in the catalog and then never tagged: 4.10.2, 4.10.3 and 4.11.11
# are all phantom versions created that way. Extracting it here lets each workflow
# publish inside its own run, where no trigger is involved.
#
# Idempotent: an existing tag is left alone and its release notes refreshed.
#
# Environment:
#   GH_TOKEN        required, for gh release create/edit
#   FORCE_ALIASES   optional, "true" re-points v<major>/v<major>.<minor> even when
#                   the tag already existed
set -euo pipefail

CAT=.github/labview-ci/catalog.json
cat_get() { python3 -c "import json,sys;print(json.load(open('$CAT')).get(sys.argv[1],'') or '')" "$1"; }

VER=$(cat_get version)
case "$VER" in
  [0-9]*.[0-9]*.[0-9]*) : ;;
  *) echo "::error::catalog version '$VER' is not MAJOR.MINOR.PATCH"; exit 1 ;;
esac

MAJOR=${VER%%.*}; REST=${VER#*.}; MINOR=${REST%%.*}
TAG="v${VER}"; MAJOR_ALIAS="v${MAJOR}"; MINOR_ALIAS="v${MAJOR}.${MINOR}"
echo "version=$VER  tag=$TAG  aliases=$MAJOR_ALIAS,$MINOR_ALIAS"

git config user.name  "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"

NEW_TAG=false
if git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null; then
  echo "Tag ${TAG} already exists."
else
  git tag -a "${TAG}" -m "LabVIEW CI ${TAG}"
  git push origin "${TAG}"
  NEW_TAG=true
  echo "Created tag ${TAG}."
fi

# The moving-alias contract: @v<major> always points at the latest release.
if [ "$NEW_TAG" = "true" ] || [ "${FORCE_ALIASES:-false}" = "true" ]; then
  for A in "$MAJOR_ALIAS" "$MINOR_ALIAS"; do
    git tag -f "$A" "$TAG^{}"
    git push -f origin "$A"
    echo "Moved alias ${A} -> ${TAG}."
  done
fi

# Rolling channel tags. `stableVersion` / `betaVersion` are set by
# promote-release.py (the owner's "Mark as stable release" button) and are absent
# until the first promotion, in which case this is a no-op. Only moves a tag when
# it is not already where it belongs.
move_channel() {
  local tier="$1" want_ver="$2"
  [ -n "$want_ver" ] || return 0
  if ! git rev-parse -q --verify "refs/tags/v${want_ver}^{}" >/dev/null; then
    echo "::warning::${tier}Version ${want_ver} has no v${want_ver} tag yet; leaving '${tier}' unchanged."
    return 0
  fi
  local want have
  want=$(git rev-parse "v${want_ver}^{}")
  have=$(git rev-parse -q --verify "refs/tags/${tier}^{}" 2>/dev/null || echo "")
  if [ "$want" != "$have" ]; then
    git tag -f "$tier" "v${want_ver}^{}"
    git push -f origin "$tier"
    echo "Moved rolling '${tier}' tag -> v${want_ver}."
  else
    echo "Rolling '${tier}' tag already at v${want_ver}."
  fi
}
move_channel stable "$(cat_get stableVersion)"
move_channel beta   "$(cat_get betaVersion)"

# Release notes come from the catalog's newest history entry.
python3 - "$CAT" > /tmp/relnotes.md <<'PY'
import json, sys
c = json.load(open(sys.argv[1], encoding='utf-8'))
rels = (c.get('history') or {}).get('releases') or []
rel = rels[0] if rels else {}
out = []
if rel.get('summary'): out += [rel['summary'], '']
if rel.get('notes'):   out += [rel['notes'], '']
for h in rel.get('highlights') or []: out.append(f'- {h}')
out += ['', 'Consumers pinned at the major alias (e.g. `@v%s`) receive this automatically.'
        % (str(c.get('version','1')).split('.')[0])]
open('/tmp/reltitle.txt','w').write(rel.get('title') or f"LabVIEW CI {c.get('version','')}")
print('\n'.join(out))
PY

if gh release view "${TAG}" >/dev/null 2>&1; then
  gh release edit "${TAG}" --title "$(cat /tmp/reltitle.txt)" --notes-file /tmp/relnotes.md
  echo "Updated release ${TAG}."
else
  gh release create "${TAG}" --target "$(git rev-parse HEAD)" \
    --title "$(cat /tmp/reltitle.txt)" --notes-file /tmp/relnotes.md
  echo "Published release ${TAG}."
fi

{
  echo "## Released ${TAG}"
  echo ""
  echo "- Immutable tag \`${TAG}\` published."
  echo "- Aliases \`${MAJOR_ALIAS}\` and \`${MINOR_ALIAS}\` now point at \`${TAG}\`."
  echo ""
  echo "Consumers pinned at \`@${MAJOR_ALIAS}\` get this update automatically — no token, no action."
} >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
