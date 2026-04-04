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

# Helper: check if NUMA is usable (returns "-XX:+UseNUMA" if available, else empty)
check_numa() {
    if /usr/local/bin/check-numa 2>/dev/null; then
        echo "-XX:+UseNUMA"
    else
        echo ""
    fi
}

# ---------- Malware Scan ----------
if [[ "${MALWARE_SCAN}" == "1" ]]; then
    if [[ ! -f "/MCAntiMalware.jar" ]]; then
        echo -e "\033[1m\033[33mcontainer@pterodactyl~ \033[0mMalware scanning is only available for Java 17 and above, skipping..."
    else
        echo -e "\033[1m\033[33mcontainer@pterodactyl~ \033[0mScanning for malware... (This may take a while)"
        java -jar /MCAntiMalware.jar --scanDirectory . --singleScan true --disableAutoUpdate true
        if [ $? -eq 0 ]; then
            echo -e "\033[1m\033[33mcontainer@pterodactyl~ \033[0mMalware scan has passed"
        else
            echo -e "\033[1m\033[33mcontainer@pterodactyl~ \033[0mMalware scan has failed"
            exit 1
        fi
    fi
else
    echo -e "\033[1m\033[33mcontainer@pterodactyl~ \033[0mSkipping malware scan..."
fi

# ---------- Automatic Updating (Leaf only) ----------
if [[ "${AUTOMATIC_UPDATING}" == "1" && "${SOFTWARE}" == "LEAF" ]]; then
    echo -e "\033[1m\033[33mcontainer@pterodactyl~ \033[0mChecking for Leaf updates..."
    # We'll use the jar's manifest or a version file.
    # Assuming the jar is named server.jar. We'll query the API for the latest build of the same Minecraft version.
    if [ -f "server.jar" ]; then
        # Try to extract Minecraft version from the jar's filename (if saved as leaf-1.21.11-97.jar)
        CURRENT_JAR=$(basename server.jar)
        if [[ "$CURRENT_JAR" =~ leaf-([0-9.]+)-([0-9]+)\.jar ]]; then
            MC_VERSION="${BASH_REMATCH[1]}"
            CURRENT_BUILD="${BASH_REMATCH[2]}"
        else
            # Fallback: read from version_history.json or leaf-version.json (if present)
            if [ -f "version_history.json" ]; then
                MC_VERSION=$(jq -r '.minecraftVersion' version_history.json 2>/dev/null)
                CURRENT_BUILD=$(jq -r '.buildNumber' version_history.json 2>/dev/null)
            else
                echo -e "\033[1m\033[33mcontainer@pterodactyl~ \033[0mCould not determine current Leaf version, skipping update."
                MC_VERSION=""
            fi
        fi
        if [[ -n "$MC_VERSION" ]]; then
            LATEST_BUILD=$(curl -s "https://api.leafmc.one/v2/projects/leaf/versions/${MC_VERSION}" | jq -r '.builds | max')
            if [[ -n "$LATEST_BUILD" && "$LATEST_BUILD" != "null" && "$LATEST_BUILD" -gt "$CURRENT_BUILD" ]]; then
                echo -e "\033[1m\033[33mcontainer@pterodactyl~ \033[0mNew Leaf build found (${LATEST_BUILD}), updating..."
                DOWNLOAD_URL="https://api.leafmc.one/v2/projects/leaf/versions/${MC_VERSION}/builds/${LATEST_BUILD}/downloads/leaf-${MC_VERSION}-${LATEST_BUILD}.jar"
                curl -s -o server.jar "$DOWNLOAD_URL"
                echo -e "\033[1m\033[33mcontainer@pterodactyl~ \033[0mUpdate complete."
            else
                echo -e "\033[1m\033[33mcontainer@pterodactyl~ \033[0mAlready on latest build (${CURRENT_BUILD})."
            fi
        fi
    else
        echo -e "\033[1m\033[33mcontainer@pterodactyl~ \033[0mserver.jar not found, skipping update."
    fi
fi

# ---------- Build the startup command ----------
# Convert placeholders {{VAR}} to ${VAR}
PARSED=$(echo "${STARTUP}" | sed -e 's/{{/${/g' -e 's/}}/}/g' | eval echo "$(cat -)")

# Insert NUMA flag if available and not already present
NUMA_FLAG=$(check_numa)
if [[ -n "$NUMA_FLAG" ]] && [[ ! "$PARSED" =~ UseNUMA ]]; then
    PARSED=$(echo "$PARSED" | sed "s/java /java $NUMA_FLAG /")
fi

# Display and run
printf "\033[1m\033[33mcontainer@pterodactyl~ \033[0m%s\n" "$PARSED"
# shellcheck disable=SC2086
exec env ${PARSED}
