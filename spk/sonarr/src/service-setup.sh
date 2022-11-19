PATH="${SYNOPKG_PKGDEST}/bin:${PATH}"
MONO_PATH="/var/packages/mono/target/bin"
MONO="${MONO_PATH}/mono"

# Sonarr uses the home directory to store it's ".config"
HOME_DIR="${SYNOPKG_PKGVAR}"
CONFIG_DIR="${SYNOPKG_PKGVAR}/.config"
SONARR_CONFIG_DIR="${CONFIG_DIR}/Sonarr"

# Sonarr v2 -> v3 compatibility:
if [ -f "${SYNOPKG_PKGDEST}/share/NzbDrone/NzbDrone.exe" ]; then
    # v2 installed
    SONARR="${SYNOPKG_PKGDEST}/share/NzbDrone/NzbDrone.exe"
    PID_FILE="${CONFIG_DIR}/NzbDrone/nzbdrone.pid"
else
    # v3 installed
    SONARR="${SYNOPKG_PKGDEST}/share/Sonarr/Sonarr.exe"
    PID_FILE="${SONARR_CONFIG_DIR}/sonarr.pid"
fi

# Allow correct Sonarr SPK version checking (v2 or v3)
if [ -f "${SYNOPKG_PKGINST_TEMP_DIR}/share/NzbDrone/NzbDrone.exe" ]; then
    # v2 SPK
    SPK_SONARR="${SYNOPKG_PKGINST_TEMP_DIR}/share/NzbDrone/NzbDrone.exe"
else
    # v3 SPK
    SPK_SONARR="${SYNOPKG_PKGINST_TEMP_DIR}/share/Sonarr/Sonarr.exe"
fi

# Some have it stored in the root of package
LEGACY_CONFIG_DIR="${SYNOPKG_PKGDEST}/.config"

# workaround for mono bug with armv5 (https://github.com/mono/mono/issues/12537)
if [ "$SYNOPKG_DSM_ARCH" == "88f6281" -o "$SYNOPKG_DSM_ARCH" == "88f6282" ]; then
    MONO="MONO_ENV_OPTIONS='-O=-aot,-float32' ${MONO}"
fi

# for DSM < 7 only:
GROUP="sc-download"
LEGACY_GROUP="sc-media"

SERVICE_COMMAND="env PATH=${MONO_PATH}:${PATH} HOME=${HOME_DIR} LD_LIBRARY_PATH=${SYNOPKG_PKGDEST}/lib ${MONO} ${SONARR}"
SVC_BACKGROUND=y
SVC_WAIT_TIMEOUT=90

service_postinst ()
{
    # Move config.xml to .config
    mkdir -p ${SONARR_CONFIG_DIR}
    mv ${SYNOPKG_PKGDEST}/app/config.xml ${SONARR_CONFIG_DIR}/config.xml
    
    echo "Set update required"
    # Make Sonarr do an update check on start to avoid possible Sonarr
    # downgrade when synocommunity package is updated
    touch ${SONARR_CONFIG_DIR}/update_required
    
    if [ ${SYNOPKG_DSM_VERSION_MAJOR} -lt 7 ]; then
        set_unix_permissions "${CONFIG_DIR}"
    fi
}

service_preupgrade ()
{
    if [ ${SYNOPKG_DSM_VERSION_MAJOR} -ge 7 ]; then
        # ensure config is in @appdata folder
        if [ -d "${LEGACY_CONFIG_DIR}" ]; then
            if [ "$(realpath ${LEGACY_CONFIG_DIR})" != "$(realpath ${CONFIG_DIR})" ]; then
                echo "Move ${LEGACY_CONFIG_DIR} to ${CONFIG_DIR}"
                mv ${LEGACY_CONFIG_DIR} ${CONFIG_DIR} 2>&1
            fi
        fi
    fi

    ## never update Sonarr distribution, use internal updater only
    [ -d ${SYNOPKG_TEMP_UPGRADE_FOLDER}/backup ] && rm -rf ${SYNOPKG_TEMP_UPGRADE_FOLDER}/backup
    echo "Backup existing distribution to ${SYNOPKG_TEMP_UPGRADE_FOLDER}/backup"
    mkdir -p ${SYNOPKG_TEMP_UPGRADE_FOLDER}/backup 2>&1
    rsync -aX ${SYNOPKG_PKGDEST}/share ${SYNOPKG_TEMP_UPGRADE_FOLDER}/backup/ 2>&1
    
    # Is Installed Sonarr Binary Ver. >= SPK Sonarr Binary Ver.?
    CUR_VER=$(${MONO_PATH}/monodis --assembly ${SONARR} | grep "Version:" | awk '{print $2}')
    echo "Installed Sonarr Binary: ${CUR_VER}"
    SPK_VER=$(${MONO_PATH}/monodis --assembly ${SPK_SONARR} | grep "Version:" | awk '{print $2}')
    echo "Requested Sonarr Binary: ${SPK_VER}"
    function version_compare() { test "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1"; }
    if version_compare $CUR_VER $SPK_VER; then
        echo 'KEEP_CUR="yes"' > ${CONFIG_DIR}/KEEP_VAR
        echo "[KEEPING] Installed Sonarr Binary - Upgrading Package Only"
        mv ${SYNOPKG_PKGDEST}/share ${SYNOPKG_PKGVAR}
    else
        echo 'KEEP_CUR="no"' > ${CONFIG_DIR}/KEEP_VAR
        echo "[REPLACING] Installed Sonarr Binary"
    fi
}

service_postupgrade ()
{
    # Restore Current Sonarr Binary If Current Ver. >= SPK Ver.
    . ${CONFIG_DIR}/KEEP_VAR
    if [ "$KEEP_CUR" == "yes" ]; then
        echo "Restoring Sonarr version from before upgrade"
        rm -fr ${SYNOPKG_PKGDEST}/share
        mv ${SYNOPKG_PKGVAR}/share ${SYNOPKG_PKGDEST}/
        set_unix_permissions "${SYNOPKG_PKGDEST}/share"
    fi

    ## restore Sonarr distribution
    if [ -d ${SYNOPKG_TEMP_UPGRADE_FOLDER}/backup/share ]; then
        echo "Restore previous distribution from ${SYNOPKG_TEMP_UPGRADE_FOLDER}/backup"
        rm -rf ${SYNOPKG_PKGDEST}/share/Lidarr/bin 2>&1
        # prevent overwrite of updated package_info
        rsync -aX --exclude=package_info ${SYNOPKG_TEMP_UPGRADE_FOLDER}/backup/share/ ${SYNOPKG_PKGDEST}/share 2>&1
    fi

    # If backup was created before new-style packages
    # new updates/backups will fail due to permissions (see #3185)
    if [ -d "/tmp/nzbdrone_backup" ] || [ -d "/tmp/nzbdrone_update" ] || [ -d "/tmp/sonarr_backup" ] || [ -d "/tmp/sonarr_update" ]; then
        set_unix_permissions "/tmp/nzbdrone_backup"
        set_unix_permissions "/tmp/nzbdrone_update"
        set_unix_permissions "/tmp/sonarr_backup"
        set_unix_permissions "/tmp/sonarr_update"
    fi

    # Remove upgrade Flag
    rm ${CONFIG_DIR}/KEEP_VAR
}
