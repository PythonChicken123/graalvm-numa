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

    # Try to get current version from version_history.json (created by Leaf)
    MC_VERSION=""
    CURRENT_BUILD=""
    if [ -f "version_history.json" ]; then
        MC_VERSION=$(jq -r '.minecraftVersion // empty' version_history.json 2>/dev/null)
        CURRENT_BUILD=$(jq -r '.buildNumber // empty' version_history.json 2>/dev/null)
    fi

    # If not found, try to get from the jar's manifest (META-INF/MANIFEST.MF)
    if [[ -z "$MC_VERSION" || -z "$CURRENT_BUILD" ]]; then
        if [ -f "server.jar" ]; then
            MANIFEST_VERSION=$(unzip -p server.jar META-INF/MANIFEST.MF 2>/dev/null | grep "Implementation-Version" | cut -d' ' -f2 | tr -d '\r')
            if [[ -n "$MANIFEST_VERSION" ]]; then
                MC_VERSION=$(echo "$MANIFEST_VERSION" | cut -d'-' -f1)
                CURRENT_BUILD=$(echo "$MANIFEST_VERSION" | cut -d'-' -f2)
            fi
        fi
    fi

    if [[ -z "$MC_VERSION" ]]; then
        echo -e "\033[1m\033[33mcontainer@pterodactyl~ \033[0mCould not determine current Leaf version, skipping update."
    else
        # Fetch latest build from API (handle empty/null response)
        API_RESPONSE=$(curl -s "https://api.leafmc.one/v2/projects/leaf/versions/${MC_VERSION}")
        LATEST_BUILD=$(echo "$API_RESPONSE" | jq -r '.builds | max // empty' 2>/dev/null)
        if [[ -n "$LATEST_BUILD" && "$LATEST_BUILD" != "null" ]]; then
            if [[ -z "$CURRENT_BUILD" || "$CURRENT_BUILD" == "null" || "$LATEST_BUILD" -gt "$CURRENT_BUILD" ]]; then
                echo -e "\033[1m\033[33mcontainer@pterodactyl~ \033[0mNew Leaf build found (${LATEST_BUILD}), updating..."
                DOWNLOAD_URL="https://api.leafmc.one/v2/projects/leaf/versions/${MC_VERSION}/builds/${LATEST_BUILD}/downloads/leaf-${MC_VERSION}-${LATEST_BUILD}.jar"
                curl -s -o server.jar "$DOWNLOAD_URL"
                echo -e "\033[1m\033[33mcontainer@pterodactyl~ \033[0mUpdate complete."
            else
                echo -e "\033[1m\033[33mcontainer@pterodactyl~ \033[0mAlready on latest build (${CURRENT_BUILD})."
            fi
        else
            echo -e "\033[1m\033[33mcontainer@pterodactyl~ \033[0mCould not fetch latest build info (API returned empty)."
        fi
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
