#!/bin/bash

# Default the TZ environment variable to UTC.
TZ=${TZ:-UTC}
export TZ

# Set environment variable that holds the Internal Docker IP
INTERNAL_IP=$(ip route get 1 | awk '{print $(NF-2);exit}')
export INTERNAL_IP

# Switch to the container's working directory
cd /home/container || exit 1

# Print Java version
printf "\033[1m\033[33mcontainer@pterodactyl~ \033[0mjava -version\n"
java -version

# Helper: check if NUMA is usable
check_numa() {
    if [[ "${NUMA_ENABLED}" == "1" ]]; then
        if /usr/local/bin/check-numa; then
            echo "-XX:+UseNUMA"
        else
            echo "NUMA requested but not available – disabling" >&2
            echo ""
        fi
    else
        echo ""
    fi
}

# Build the final startup command
# The egg provides STARTUP with placeholders like {{SERVER_JARFILE}}, {{MEMORY}}, etc.
# We also inject the NUMA flag if enabled.
PARSED=$(echo "${STARTUP}" | sed -e 's/{{/${/g' -e 's/}}/}/g' | eval echo "$(cat -)")

# Insert NUMA flag before the -jar part (simple approach: add to beginning of java command)
if [[ -n "$(check_numa)" ]]; then
    PARSED=$(echo "$PARSED" | sed "s/java /java $(check_numa) /")
fi

# Display the command we're running
printf "\033[1m\033[33mcontainer@pterodactyl~ \033[0m%s\n" "$PARSED"
# shellcheck disable=SC2086
exec env ${PARSED}
