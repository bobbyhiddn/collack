#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIRECTORY="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIRECTORY
readonly ROUTE_FILE="$SCRIPT_DIRECTORY/callack-route.json"
readonly APP_URL="http://127.0.0.1:7912/"
readonly SHORE_URL="http://127.0.0.1:7778"
readonly SHORE_HEALTH_URL="$SHORE_URL/health"
readonly SHORE_REGISTRY_URL="$SHORE_URL/api/dock/services"
readonly SHORE_REGISTER_URL="$SHORE_REGISTRY_URL/register"
readonly SHORE_ROUTE_URL="$SHORE_URL/collack/"
readonly MAX_ATTEMPTS=60

force_registration=false
if [[ "${1:-}" == "--force" ]]; then
    force_registration=true
elif [[ -n "${1:-}" ]]; then
    echo "usage: $0 [--force]" >&2
    exit 2
fi

wait_for_url() {
    local label="$1"
    local url="$2"
    local attempt

    for ((attempt = 1; attempt <= MAX_ATTEMPTS; attempt += 1)); do
        if /usr/bin/curl \
            --fail \
            --silent \
            --connect-timeout 1 \
            --max-time 2 \
            --output /dev/null \
            "$url"; then
            return 0
        fi
        /usr/bin/sleep 1
    done

    echo "timed out waiting for $label at $url" >&2
    return 1
}

wait_for_url "Callack" "$APP_URL"
wait_for_url "Shore" "$SHORE_HEALTH_URL"

if [[ "$force_registration" == false ]]; then
    registry_json="$(
        /usr/bin/curl \
            --fail \
            --silent \
            --show-error \
            --connect-timeout 1 \
            --max-time 3 \
            "$SHORE_REGISTRY_URL"
    )"

    registration_time="$(
        /usr/bin/jq \
            --raw-output \
            --slurpfile expected "$ROUTE_FILE" \
            '
                first(
                    .services[]
                    | select(
                        .name == $expected[0].name
                        and .description == $expected[0].description
                        and .category == $expected[0].category
                        and .tags == $expected[0].tags
                        and .mode == $expected[0].mode
                        and .port == $expected[0].port
                        and .health_endpoint == $expected[0].health_endpoint
                    )
                    | .registered_at
                ) // empty
            ' <<<"$registry_json"
    )"
    shore_start_time="$(
        /usr/bin/systemctl \
            --user \
            show shore.service \
            --property=ActiveEnterTimestamp \
            --value
    )"

    registration_epoch=0
    shore_start_epoch=1
    if [[ -n "$registration_time" ]] \
        && registration_epoch="$(
            /usr/bin/date --date="$registration_time" +%s
        )" \
        && shore_start_epoch="$(
            /usr/bin/date --date="$shore_start_time" +%s
        )" \
        && ((registration_epoch >= shore_start_epoch)) \
        && /usr/bin/curl \
            --fail \
            --silent \
            --head \
            --connect-timeout 1 \
            --max-time 3 \
            --output /dev/null \
            "$SHORE_ROUTE_URL"; then
        echo "Callack Shore route is already current"
        exit 0
    fi
fi

/usr/bin/curl \
    --fail-with-body \
    --silent \
    --show-error \
    --connect-timeout 1 \
    --max-time 5 \
    --output /dev/null \
    --request POST \
    --header "Content-Type: application/json" \
    --data-binary "@$ROUTE_FILE" \
    "$SHORE_REGISTER_URL"

wait_for_url "Callack's Shore route" "$SHORE_ROUTE_URL"
echo "Callack Shore route registered"
