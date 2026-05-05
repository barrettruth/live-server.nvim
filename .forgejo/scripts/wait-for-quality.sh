#!/usr/bin/env bash
set -eu

token="${FORGEJO_TOKEN:-}"
api_url="${FORGEJO_API_URL:-}"
server_url="${FORGEJO_SERVER_URL:-}"
repository="${FORGEJO_REPOSITORY:-}"
sha="${FORGEJO_SHA:-}"

if [ -z "$api_url" ] && [ -n "$server_url" ]; then
	api_url="${server_url%/}/api/v1"
fi
api_url="${api_url%/}"

if [ -z "$token" ] || [ -z "$api_url" ] || [ -z "$repository" ] || [ -z "$sha" ]; then
	echo "Missing Forgejo Actions environment for quality wait." >&2
	exit 1
fi

required_contexts='quality / Format (push)
quality / Lint (push)'
if grep -q '^  test:' .forgejo/workflows/quality.yaml; then
	required_contexts="${required_contexts}
quality / Test (push)"
fi

deadline="$(($(date +%s) + 3600))"
last_pending=""
while [ "$(date +%s)" -lt "$deadline" ]; do
	payload="$(curl -fsSL \
		-H "Authorization: token $token" \
		"$api_url/repos/$repository/commits/$sha/status")"
	pending=""
	failed=""

	while IFS= read -r context; do
		[ -n "$context" ] || continue
		status="$(printf '%s' "$payload" | jq -r --arg context "$context" '[.statuses[]? | select(.context == $context)][0].status // ""')"
		case "$status" in
		success) ;;
		error | failure) failed="${failed}${failed:+, }${context}" ;;
		*) pending="${pending}${pending:+, }${context}" ;;
		esac
	done <<CONTEXTS
$required_contexts
CONTEXTS

	if [ -n "$failed" ]; then
		echo "Quality checks failed: $failed" >&2
		exit 1
	fi
	if [ -z "$pending" ]; then
		echo "Quality checks passed."
		exit 0
	fi

	if [ "$pending" != "$last_pending" ]; then
		echo "Waiting for quality checks: $pending"
		last_pending="$pending"
	fi
	sleep 10
done

echo "Timed out waiting for quality checks." >&2
exit 1
