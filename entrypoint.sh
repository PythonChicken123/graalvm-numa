#!/bin/bash

# Default the TZ environment variable to UTC.
TZ=${TZ:-UTC}
export TZ

# Set environment variable that holds the Internal Docker IP
INTERNAL_IP=$(ip route get 1 | awk '{print $(NF-2);exit}')
export INTERNAL_IP

# Switch to the working directory
cd /home/container || exit 1

# Performance: Drop caches to ensure contiguous memory for HugePages/PreTouch
# Requires the container to be running as root/privileged
sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null

# Print Java version
printf "\033[1m\033[33mcontainer@pterodactyl~ \033[0mjava -version\n"
java -version

# Helper: check if NUMA is usable (Crucial for Xanmod/GraalVM)
check_numa() {
    if [ -f /usr/local/bin/check-numa ] && /usr/local/bin/check-numa 2>/dev/null; then
        echo "-XX:+UseNUMA"
    elif [ -d /sys/devices/system/node/node0 ]; then
        echo "-XX:+UseNUMA"
    else
        echo ""
    fi
}

# ---------- Malware Scan ----------
if [[ "${MALWARE_SCAN}" == "1" ]]; then
    if [[ ! -f "/MCAntiMalware.jar" ]]; then
        echo -e "\033[1m\033[33mcontainer@pterodactyl~ \033[0mMalware scanning jar not found, skipping..."
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

# ---------- Automatic Updating ----------
if [[ "${AUTOMATIC_UPDATING}" == "1" ]]; then
    if [[ "${SOFTWARE}" == "LEAF" ]]; then
        echo -e "\033[1m\033[33mcontainer@pterodactyl~ \033[0mChecking for Leaf updates..."
        MC_VERSION=""
        CURRENT_BUILD=""

        if [ -f "version_history.json" ]; then
            RAW_VERSION=$(jq -r '.currentVersion // empty' version_history.json 2>/dev/null)
            if [[ -n "$RAW_VERSION" ]]; then
                MC_VERSION=$(echo "$RAW_VERSION" | sed -n 's/^\([0-9]\+\.[0-9]\+\.[0-9]\+\)-.*$/\1/p')
                CURRENT_BUILD=$(echo "$RAW_VERSION" | sed -n 's/^[0-9]\+\.[0-9]\+\.[0-9]\+-\([0-9]\+\)-.*$/\1/p')
            fi
        fi

        if [[ -z "$MC_VERSION" || -z "$CURRENT_BUILD" ]]; then
            if [ -f "server.jar" ]; then
                MANIFEST_VERSION=$(unzip -p server.jar META-INF/MANIFEST.MF 2>/dev/null | grep "Implementation-Version" | cut -d' ' -f2 | tr -d '\r')
                if [[ -n "$MANIFEST_VERSION" ]]; then
                    MC_VERSION=$(echo "$MANIFEST_VERSION" | cut -d'-' -f1)
                    CURRENT_BUILD=$(echo "$MANIFEST_VERSION" | cut -d'-' -f2)
                fi
            fi
        fi

        if [[ -n "$MC_VERSION" ]]; then
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
            fi
        fi
    else
        echo -e "\033[1m\033[33mcontainer@pterodactyl~ \033[0mChecking for MCJars updates..."
        if [ -f "server.jar" ]; then
            HASH=$(sha256sum server.jar | awk '{print $1}')
            API_RESPONSE=$(curl -s "https://mcjars.app/api/v1/build/$HASH")
            SUCCESS=$(echo "$API_RESPONSE" | jq -r '.success // false')
            if [[ "$SUCCESS" == "true" ]]; then
                CURRENT_ID=$(echo "$API_RESPONSE" | jq -r '.build.id')
                LATEST_ID=$(echo "$API_RESPONSE" | jq -r '.latest.id')
                if [[ -n "$CURRENT_ID" && -n "$LATEST_ID" && "$CURRENT_ID" != "$LATEST_ID" ]]; then
                    echo -e "\033[1m\033[33mcontainer@pterodactyl~ \033[0mNew build found (${LATEST_ID}), updating..."
                    bash <(curl -s "https://mcjars.app/api/v1/script/$LATEST_ID/bash?echo=false")
                    echo -e "\033[1m\033[33mcontainer@pterodactyl~ \033[0mUpdate complete."
                else
                    echo -e "\033[1m\033[33mcontainer@pterodactyl~ \033[0mAlready on latest build (${CURRENT_ID})."
                fi
            fi
        fi
    fi
fi

# ---------- Build the startup command ----------

# Replace Pterodactyl variables {{VAR}} with shell variables ${VAR}
MODIFIED_STARTUP=$(echo -e "${STARTUP}" | sed -e 's/{{/${/g' -e 's/}}/}/g')

# Resolve the RAM calculation and environment variables
PARSED=$(eval echo -e "${MODIFIED_STARTUP}")

# Inject NUMA flag for Xanmod optimization
NUMA_FLAG=$(check_numa)
if [[ -n "$NUMA_FLAG" ]] && [[ ! "$PARSED" =~ "UseNUMA" ]]; then
    PARSED=$(echo "$PARSED" | sed -E "s/(^| )java/& $NUMA_FLAG/")
fi

# Clean up whitespace and display
PARSED=$(echo "$PARSED" | tr -s ' ')
printf "\033[1m\033[33mcontainer@pterodactyl~ \033[0m%s\n" "$PARSED"

# Execute the process directly to preserve Linux Capabilities (SYS_NICE, etc.)
# shellcheck disable=SC2086
exec ${PARSED}
