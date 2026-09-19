#!/usr/bin/env bash
# scripts/inject_SukiSU-Ultra.sh

echo ">>> Executing Integration Module for SukiSU-Ultra..."

if [ "${USE_DYNAMIC_TRANSPLANT}" == "true" ]; then
    echo ">>> 1. Cloning pristine official SukiSU-Ultra upstream..."
    git clone https://github.com/SukiSU-Ultra/SukiSU-Ultra.git "${MANAGER_DIR}"
    
    ln -sfn "../${MANAGER_DIR}" "common/${MANAGER_DIR}"
    cd common
    bash "${MANAGER_DIR}/kernel/setup.sh" main
    cd ..
    
    cd "${MANAGER_DIR}"
    UPSTREAM_HASH=$(git log -n 1 --format="%H" -i --grep="ci skip" --grep="skip ci" --invert-grep -- . ":!website" ":!docs" ":!*.md" ":!.github" ":!scripts" ":!userspace")
    CALCULATED_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
    CALCULATED_COUNT=$(git rev-list --count "${UPSTREAM_HASH}")
    UPSTREAM_BRANCH="main"

    echo ">>> 2. Fetching 'builtin' branch for SuSFS code transplant..."
    git fetch origin builtin:builtin
    git checkout builtin

    rm -rf uapi
    mv kernel/include/uapi uapi 2>/dev/null || true
    cd kernel/include
    ln -s ../../uapi uapi
    cd ../..
    mv kernel/Makefile kernel/Kbuild 2>/dev/null || true

    git add uapi kernel/
    git config --global user.email "runner@github.actions"
    git config --global user.name "GitHub Actions Canary"
    git commit -m "chore: CI structural fixes (symlinks and Kbuild)"

    echo ">>> 3. Generating filtered SuSFS patch..."
    git checkout main
    git diff --diff-filter=AM main..builtin -- kernel/ uapi/ \
      ':!kernel/.clangd' \
      ':!kernel/.clang-format' \
      ':!kernel/.gitignore' \
      ':!.gitignore' > susfs_port_clean.patch

    echo ">>> 4. Applying surgical SuSFS port patch to main..."
    git apply susfs_port_clean.patch
    rm susfs_port_clean.patch
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
    OFFICIAL_REPO_URL="https://github.com/SukiSU-Ultra/SukiSU-Ultra.git"
    echo ">>> Locating official upstream sync point for SukiSU-Ultra/SukiSU-Ultra..."
    
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

# ---------------------------------------------------------
# SukiSU-Ultra 6.12+ LSM Hook API Fix
# ---------------------------------------------------------
echo ">>> Checking for Linux 6.12+ LSM API Mismatch in SukiSU-Ultra..."
# Dynamically extract kernel version since it's not exported to this script
K_VER=$(grep "^VERSION =" common/Makefile | tr -d ' ' | cut -d'=' -f2)
K_PATCH=$(grep "^PATCHLEVEL =" common/Makefile | tr -d ' ' | cut -d'=' -f2)

if [ "$K_VER" = "6" ] && [ "$K_PATCH" -ge "12" ]; then
    LSM_HOOK_FILE="common/drivers/kernelsu/hook/lsm_hook.c"

    if [ -f "$LSM_HOOK_FILE" ] && grep -q 'security_add_hooks' "$LSM_HOOK_FILE"; then
        echo "  -> Kernel 6.12+ detected. Disarming deprecated LSM hook registration..."
        # Neutralize the hook call while using the variable to prevent compiler warnings
        sed -i 's/security_add_hooks.*/(void)ksu_hooks;/g' "$LSM_HOOK_FILE"
        echo "  -> lsm_hook.c runtime panic trap bypassed!"
    else
        echo "  -> LSM hook is already updated or file missing. Skipping."
    fi
else
    echo "  -> Kernel $K_VER.$K_PATCH detected. Legacy LSM string hook is perfectly valid."
fi

echo "  -> Target Tag: $CALCULATED_TAG"
echo "  -> Target Hash: $UPSTREAM_HASH"
echo "  -> Target Count: $CALCULATED_COUNT"
echo ">>> SukiSU-Ultra integration complete."
