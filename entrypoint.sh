#!/bin/bash

# 1. Environment & Network Setup
TZ=${TZ:-UTC}
export TZ
INTERNAL_IP=$(ip route get 1 | awk '{print $(NF-2);exit}')
export INTERNAL_IP

# Switch to working directory
cd /home/container || exit 1

# Performance: Ensure filesystem sync
sync

printf "\033[1m\033[33mcontainer@pterodactyl~ \033[0mjava -version\n"
java -version

# Helper: check if NUMA is usable via Dockerfile helper
check_numa() {
    if /usr/local/bin/check-numa 2>/dev/null; then
        echo "-XX:+UseNUMA"
    else
        # Fallback check for the library link creation
        if [ -f /usr/lib/x86_64-linux-gnu/libnuma.so ] || [ -f /usr/lib/aarch64-linux-gnu/libnuma.so ]; then
            echo "-XX:+UseNUMA"
        else
            echo ""
        fi
    fi
}

# 2. ---------- Malware Scan ----------
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

# 3. ---------- Automatic Updating (Leaf & MCJars) ----------
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
                LATEST_ID=$(echo "$API_RESPONSE" | jq -r '.latest.id')
                if [[ $(echo "$API_RESPONSE" | jq -r '.build.id') != "$LATEST_ID" ]]; then
                    echo -e "\033[1m\033[33mcontainer@pterodactyl~ \033[0mUpdating to latest build (${LATEST_ID})..."
                    bash <(curl -s "https://mcjars.app/api/v1/script/$LATEST_ID/bash?echo=false")
                fi
            fi
        fi
    fi
fi

# 4. ---------- Startup Command Construction ----------
# Replace Pterodactyl variables {{VAR}} with shell variables ${VAR}
MODIFIED_STARTUP=$(echo -e "${STARTUP}" | sed -e 's/{{/${/g' -e 's/}}/}/g')

# Evaluate the string to resolve the environment variables (including RAM math)
PARSED=$(eval echo -e "${MODIFIED_STARTUP}")

# Inject NUMA flag if supported/detected
NUMA_FLAG=$(check_numa)
if [[ -n "$NUMA_FLAG" ]] && [[ ! "$PARSED" =~ "UseNUMA" ]]; then
    PARSED=$(echo "$PARSED" | sed -E "s/(^| )java/& $NUMA_FLAG/")
fi

# Display the final command
PARSED=$(echo "$PARSED" | tr -s ' ')
printf "\033[1m\033[33mcontainer@pterodactyl~ \033[0m%s\n" "$PARSED"

# 5. ---------- Execution ----------
# exec ensures the Java process takes over PID 1, crucial for Xanmod priority handling
exec ${PARSED}
