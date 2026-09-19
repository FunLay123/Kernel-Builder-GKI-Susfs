#!/usr/bin/env bash
# scripts/inject_ReSukiSU.sh

echo ">>> Executing Integration Module for ReSukiSU..."

if [ "${USE_DYNAMIC_TRANSPLANT}" == "true" ]; then
    echo ">>> 1. Cloning pristine official ReSukiSU upstream..."
    git clone https://github.com/ReSukiSU/ReSukiSU.git "${MANAGER_DIR}"
    
    ln -sfn "../${MANAGER_DIR}" "common/${MANAGER_DIR}"
    cd common
    bash "${MANAGER_DIR}/kernel/setup.sh" main
    cd ..
    
    cd "${MANAGER_DIR}"
    UPSTREAM_HASH=$(git log -n 1 --format="%H" -i --grep="ci skip" --grep="skip ci" --invert-grep -- . ":!website" ":!docs" ":!*.md" ":!.github" ":!scripts" ":!userspace")
    CALCULATED_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
    CALCULATED_COUNT=$(git rev-list --count "${UPSTREAM_HASH}")
    UPSTREAM_BRANCH="main"

    echo ">>> 2. Applying dynamic Kleaf bypass & Kconfig overrides..."
    sed -i 's/default KSU_TRACEPOINT_HOOK/default KSU_SUSFS/g' kernel/Kconfig
    sed -i 's/bool "Tracepoint Syscall Redirect"/bool "Tracepoint Syscall Redirect"\n\t\tdepends on n/g' kernel/Kconfig
    sed -i 's/depends on KSU != m/depends on n/g' kernel/Kconfig
    sed -i 's/ifeq ($(shell test -e $(srctree)\/fs\/susfs.c.*/ifeq (0,0)/g' kernel/Kbuild
    sed -i 's/cat $(srctree)\/include\/linux\/susfs.h |/cat $(srctree)\/include\/linux\/susfs.h 2>\/dev\/null |/g' kernel/Kbuild
    cd ..
else
    echo ">>> Safe fallback channel detected. Cloning custom pipeline branch..."
    git clone -b "${KSU_VARIANT_REF}" "${KSU_VARIANT_REPO_URL}" "${MANAGER_DIR}"
    
    ln -sfn "../${MANAGER_DIR}" "common/${MANAGER_DIR}"
    cd common
    # FIX 1: Pass the dynamic reference instead of hardcoded 'main'
    bash "${MANAGER_DIR}/kernel/setup.sh" "${KSU_VARIANT_REF}"
    cd ..
    
    # FIX 2: Lock the upstream tracking variable to the dynamic branch
    UPSTREAM_BRANCH="${KSU_VARIANT_REF}"
    
    cd "${MANAGER_DIR}"
    
    # FIX 3: Fetch official upstream and calculate the pristine Merge-Base
    OFFICIAL_REPO_URL="https://github.com/ReSukiSU/ReSukiSU.git"
    echo ">>> Locating official upstream sync point for ReSukiSU/ReSukiSU..."
    
    # We fetch 'main' from the official repo because that is their core tracking branch
    git fetch --quiet "${OFFICIAL_REPO_URL}" main
    RAW_BASE=$(git merge-base HEAD FETCH_HEAD)
    
    # FIX 4: Calculate Hash, Count, and Tag starting strictly from the pristine base commit
    set +o pipefail
    UPSTREAM_HASH=$(git log -n 1 --first-parent "${RAW_BASE}" --format="%H" -i --grep="ci skip" --grep="skip ci" --invert-grep -- . ":!website" ":!docs" ":!*.md" ":!.github" ":!scripts" ":!userspace")
    set -o pipefail
    
    CALCULATED_COUNT=$(git rev-list --count "${UPSTREAM_HASH}" 2>/dev/null || echo "11950")
    CALCULATED_TAG=$(git describe --tags --abbrev=0 "${UPSTREAM_HASH}" 2>/dev/null || echo "v0.0.0")
    
    cd ..
fi

echo "  -> Target Tag: $CALCULATED_TAG"
echo "  -> Target Hash: $UPSTREAM_HASH"
echo "  -> Target Count: $CALCULATED_COUNT"
echo ">>> ReSukiSU integration complete."
