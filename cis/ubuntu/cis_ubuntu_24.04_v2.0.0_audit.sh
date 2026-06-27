#!/usr/bin/env bash

set -o pipefail

SCRIPT_NAME="cis_ubuntu_24.04_v2.0.0_audit.sh"
DEFAULT_PROFILE="l1-server"
PROFILE="$DEFAULT_PROFILE"
SECTION_FILTER=""
CONTROL_FILTER=""
EXCLUDE_FILTER=""
NO_COLOR=0
PASS_COUNT=0
FAIL_COUNT=0
MANUAL_COUNT=0
NA_COUNT=0
TOTAL_COUNT=0

print_banner() {
    cat <<'EOF'
============================================================
 Script:    cis_ubuntu_24.04_v3.0.0_audit.sh
 Author:    Kaiyuann
 Copyright: Copyright (c) 2026 Kaiyuann
 License:   Apache License 2.0
 GitHub:    https://github.com/Kaiyuann/hardening-scripts
============================================================
EOF
}

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [options]

Options:
  --profile PROFILE   l1-server, l2-server, l1-workstation, l2-workstation
  --section LIST      Comma-separated section prefixes to include, e.g. 1,1.1
  --control LIST      Comma-separated control IDs to include
  --exclude LIST      Comma-separated control IDs to exclude
  --no-color          Disable colored output
  -h, --help          Show this help
EOF
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --profile)
                [ "$#" -ge 2 ] || { printf '%s\n' "ERROR: --profile requires a value" >&2; exit 1; }
                PROFILE="$2"
                shift 2
                ;;
            --profile=*)
                PROFILE="${1#*=}"
                shift
                ;;
            --section)
                [ "$#" -ge 2 ] || { printf '%s\n' "ERROR: --section requires a value" >&2; exit 1; }
                SECTION_FILTER="$2"
                shift 2
                ;;
            --section=*)
                SECTION_FILTER="${1#*=}"
                shift
                ;;
            --control)
                [ "$#" -ge 2 ] || { printf '%s\n' "ERROR: --control requires a value" >&2; exit 1; }
                CONTROL_FILTER="$2"
                shift 2
                ;;
            --control=*)
                CONTROL_FILTER="${1#*=}"
                shift
                ;;
            --exclude)
                [ "$#" -ge 2 ] || { printf '%s\n' "ERROR: --exclude requires a value" >&2; exit 1; }
                EXCLUDE_FILTER="$2"
                shift 2
                ;;
            --exclude=*)
                EXCLUDE_FILTER="${1#*=}"
                shift
                ;;
            --no-color)
                NO_COLOR=1
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                printf 'ERROR: Unknown option: %s\n' "$1" >&2
                usage >&2
                exit 1
                ;;
        esac
    done

    case "$PROFILE" in
        l1-server|l2-server|l1-workstation|l2-workstation) ;;
        *)
            printf 'ERROR: Invalid profile: %s\n' "$PROFILE" >&2
            usage >&2
            exit 1
            ;;
    esac
}

require_root() {
    if [ "${EUID:-$(id -u)}" -ne 0 ]; then
        printf 'ERROR: This script must be run as root. Try: sudo ./%s\n' "$SCRIPT_NAME" >&2
        exit 1
    fi
}

setup_colors() {
    if [ "$NO_COLOR" -eq 1 ] || [ ! -t 1 ]; then
        GREEN=""
        RED=""
        PURPLE=""
        BLUE=""
        RESET=""
    else
        GREEN="$(printf '\033[32m')"
        RED="$(printf '\033[31m')"
        PURPLE="$(printf '\033[35m')"
        BLUE="$(printf '\033[34m')"
        RESET="$(printf '\033[0m')"
    fi
}

print_result() {
    status="$1"
    control_id="$2"
    title="$3"
    color="$4"

    printf '%b[%s]%b\t%s %s\n' "$color" "$status" "$RESET" "$control_id" "$title"
}

pass_control() {
    PASS_COUNT=$((PASS_COUNT + 1))
    TOTAL_COUNT=$((TOTAL_COUNT + 1))
    print_result "PASS" "$1" "$2" "$GREEN"
}

fail_control() {
    FAIL_COUNT=$((FAIL_COUNT + 1))
    TOTAL_COUNT=$((TOTAL_COUNT + 1))
    print_result "FAIL" "$1" "$2" "$RED"
}

manual_control() {
    MANUAL_COUNT=$((MANUAL_COUNT + 1))
    TOTAL_COUNT=$((TOTAL_COUNT + 1))
    print_result "MANUAL" "$1" "$2" "$PURPLE"
}

na_control() {
    NA_COUNT=$((NA_COUNT + 1))
    TOTAL_COUNT=$((TOTAL_COUNT + 1))
    print_result "N/A" "$1" "$2" "$BLUE"
}

print_summary() {
    printf '%s\n' "============================================================"
    printf '%s\n' "Audit Summary"
    printf '%s\n' "============================================================"
    printf 'Profile: %s\n' "$PROFILE"
    [ -n "$SECTION_FILTER" ] && printf 'Section filter: %s\n' "$SECTION_FILTER"
    [ -n "$CONTROL_FILTER" ] && printf 'Control filter: %s\n' "$CONTROL_FILTER"
    [ -n "$EXCLUDE_FILTER" ] && printf 'Exclude filter: %s\n' "$EXCLUDE_FILTER"
    printf 'Total:  %s\n' "$TOTAL_COUNT"
    printf '%bPass:%b   %s\n' "$GREEN" "$RESET" "$PASS_COUNT"
    printf '%bFail:%b   %s\n' "$RED" "$RESET" "$FAIL_COUNT"
    printf '%bManual:%b %s\n' "$PURPLE" "$RESET" "$MANUAL_COUNT"
    printf '%bN/A:%b    %s\n' "$BLUE" "$RESET" "$NA_COUNT"
    printf '%s\n' "============================================================"
}

list_has_value() {
    local list="$1"
    local value="$2"
    local item
    local items

    IFS=',' read -r -a items <<< "$list"
    for item in "${items[@]}"; do
        item="$(printf '%s' "$item" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        [ "$item" = "$value" ] && return 0
    done

    return 1
}

section_matches() {
    local control_id="$1"
    local section
    local sections

    [ -z "$SECTION_FILTER" ] && return 0

    IFS=',' read -r -a sections <<< "$SECTION_FILTER"
    for section in "${sections[@]}"; do
        section="$(printf '%s' "$section" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        case "$control_id" in
            "$section"|"$section".*) return 0 ;;
        esac
    done

    return 1
}

profile_matches() {
    applicability="$1"

    case "$PROFILE:$applicability" in
        l1-server:*l1-server*) return 0 ;;
        l2-server:*l1-server*|l2-server:*l2-server*) return 0 ;;
        l1-workstation:*l1-workstation*) return 0 ;;
        l2-workstation:*l1-workstation*|l2-workstation:*l2-workstation*) return 0 ;;
    esac

    return 1
}

should_run_control() {
    control_id="$1"
    applicability="$2"

    profile_matches "$applicability" || return 1
    section_matches "$control_id" || return 1

    if [ -n "$CONTROL_FILTER" ] && ! list_has_value "$CONTROL_FILTER" "$control_id"; then
        return 1
    fi

    if [ -n "$EXCLUDE_FILTER" ] && list_has_value "$EXCLUDE_FILTER" "$control_id"; then
        return 1
    fi

    return 0
}

module_config_name() {
    printf '%s' "$1" | tr '-' '_'
}

module_loaded_regex() {
    module_name="$1"
    printf '%s' "$module_name" | sed 's/-/(_|-)/g'
}

kernel_module_exists() {
    module_name="$1"
    module_type="$2"
    module_path_name="${module_name//-/\/}"

    while IFS= read -r module_path; do
        if [ -d "$module_path/$module_path_name" ] && [ -n "$(ls -A "$module_path/$module_path_name" 2>/dev/null)" ]; then
            return 0
        fi
    done < <(readlink -e "/usr/lib/modules/"*"/kernel/$module_type" 2>/dev/null || readlink -e "/lib/modules/"*"/kernel/$module_type" 2>/dev/null)

    return 1
}

kernel_module_is_loaded() {
    module_name="$1"
    loaded_regex="$(module_loaded_regex "$module_name")"

    lsmod | awk '{print $1}' | grep -Pq -- "^${loaded_regex}$"
}

kernel_module_is_not_loadable() {
    module_name="$1"
    config_name="$(module_config_name "$module_name")"

    modprobe --showconfig 2>/dev/null \
        | grep -Pq -- "^\h*install\h+${config_name}\h+(/usr)?/bin/(true|false)\b"
}

kernel_module_is_blacklisted() {
    module_name="$1"
    config_name="$(module_config_name "$module_name")"

    modprobe --showconfig 2>/dev/null \
        | grep -Pq -- "^\h*blacklist\h+${config_name}\b"
}

audit_kernel_module_not_available() {
    control_id="$1"
    title="$2"
    module_name="$3"
    module_type="$4"
    applicability="$5"

    should_run_control "$control_id" "$applicability" || return 0

    if ! kernel_module_exists "$module_name" "$module_type"; then
        pass_control "$control_id" "$title"
        return 0
    fi

    if kernel_module_is_loaded "$module_name"; then
        fail_control "$control_id" "$title"
        return 0
    fi

    if ! kernel_module_is_not_loadable "$module_name"; then
        fail_control "$control_id" "$title"
        return 0
    fi

    if ! kernel_module_is_blacklisted "$module_name"; then
        fail_control "$control_id" "$title"
        return 0
    fi

    pass_control "$control_id" "$title"
}

audit_1_1_1_1() {
    audit_kernel_module_not_available \
        "1.1.1.1" \
        "Ensure cramfs kernel module is not available" \
        "cramfs" \
        "fs" \
        "l1-server,l1-workstation"
}

audit_1_1_1_2() {
    audit_kernel_module_not_available \
        "1.1.1.2" \
        "Ensure freevxfs kernel module is not available" \
        "freevxfs" \
        "fs" \
        "l1-server,l1-workstation"
}

audit_1_1_1_3() {
    audit_kernel_module_not_available \
        "1.1.1.3" \
        "Ensure hfs kernel module is not available" \
        "hfs" \
        "fs" \
        "l1-server,l1-workstation"
}

audit_1_1_1_4() {
    audit_kernel_module_not_available \
        "1.1.1.4" \
        "Ensure hfsplus kernel module is not available" \
        "hfsplus" \
        "fs" \
        "l1-server,l1-workstation"
}

audit_1_1_1_5() {
    audit_kernel_module_not_available \
        "1.1.1.5" \
        "Ensure jffs2 kernel module is not available" \
        "jffs2" \
        "fs" \
        "l1-server,l1-workstation"
}

audit_1_1_1_6() {
    audit_kernel_module_not_available \
        "1.1.1.6" \
        "Ensure overlay kernel module is not available" \
        "overlay" \
        "fs" \
        "l2-server,l2-workstation"
}

audit_1_1_1_7() {
    audit_kernel_module_not_available \
        "1.1.1.7" \
        "Ensure squashfs kernel module is not available" \
        "squashfs" \
        "fs" \
        "l2-server,l2-workstation"
}

audit_1_1_1_8() {
    audit_kernel_module_not_available \
        "1.1.1.8" \
        "Ensure udf kernel module is not available" \
        "udf" \
        "fs" \
        "l2-server,l2-workstation"
}

audit_1_1_1_9() {
    audit_kernel_module_not_available \
        "1.1.1.9" \
        "Ensure firewire-core kernel module is not available" \
        "firewire-core" \
        "drivers" \
        "l1-server,l2-workstation"
}

audit_1_1_1_10() {
    audit_kernel_module_not_available \
        "1.1.1.10" \
        "Ensure usb-storage kernel module is not available" \
        "usb-storage" \
        "drivers" \
        "l1-server,l2-workstation"
}

audit_1_1_1_11() {
    control_id="1.1.1.11"
    title="Ensure unused filesystems kernel modules are not available"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0
    manual_control "$control_id" "$title"
}

mount_exists() {
    mount_point="$1"

    findmnt -kn "$mount_point" >/dev/null 2>&1
}

systemd_mount_not_disabled_or_masked() {
    unit="$1"
    state="$(systemctl is-enabled "$unit" 2>/dev/null)"

    [ -n "$state" ] || return 1

    case "$state" in
        disabled|masked) return 1 ;;
        *) return 0 ;;
    esac
}

mount_has_option() {
    mount_point="$1"
    option="$2"
    options="$(findmnt -kn -o OPTIONS "$mount_point" 2>/dev/null)"

    printf '%s' "$options" | grep -Eq "(^|,)$option(,|$)"
}

audit_mount_point_exists_with_unit() {
    control_id="$1"
    title="$2"
    mount_point="$3"
    unit="$4"
    applicability="$5"

    should_run_control "$control_id" "$applicability" || return 0

    if mount_exists "$mount_point" && systemd_mount_not_disabled_or_masked "$unit"; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_mount_option() {
    control_id="$1"
    title="$2"
    mount_point="$3"
    option="$4"
    applicability="$5"

    should_run_control "$control_id" "$applicability" || return 0

    if ! mount_exists "$mount_point"; then
        na_control "$control_id" "$title"
    elif mount_has_option "$mount_point" "$option"; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_mount_point_exists() {
    control_id="$1"
    title="$2"
    mount_point="$3"
    applicability="$4"

    should_run_control "$control_id" "$applicability" || return 0

    if mount_exists "$mount_point"; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_1_1_2_1_1() {
    audit_mount_point_exists_with_unit \
        "1.1.2.1.1" \
        "Ensure /tmp is tmpfs or a separate partition" \
        "/tmp" \
        "tmp.mount" \
        "l1-server,l1-workstation"
}

audit_1_1_2_1_2() {
    audit_mount_option \
        "1.1.2.1.2" \
        "Ensure nodev option set on /tmp partition" \
        "/tmp" \
        "nodev" \
        "l1-server,l1-workstation"
}

audit_1_1_2_1_3() {
    audit_mount_option \
        "1.1.2.1.3" \
        "Ensure nosuid option set on /tmp partition" \
        "/tmp" \
        "nosuid" \
        "l1-server,l1-workstation"
}

audit_1_1_2_1_4() {
    audit_mount_option \
        "1.1.2.1.4" \
        "Ensure noexec option set on /tmp partition" \
        "/tmp" \
        "noexec" \
        "l1-server,l1-workstation"
}

audit_1_1_2_2_1() {
    audit_mount_point_exists \
        "1.1.2.2.1" \
        "Ensure /dev/shm is tmpfs or a separate partition" \
        "/dev/shm" \
        "l1-server,l1-workstation"
}

audit_1_1_2_2_2() {
    audit_mount_option \
        "1.1.2.2.2" \
        "Ensure nodev option set on /dev/shm partition" \
        "/dev/shm" \
        "nodev" \
        "l1-server,l1-workstation"
}

audit_1_1_2_2_3() {
    audit_mount_option \
        "1.1.2.2.3" \
        "Ensure nosuid option set on /dev/shm partition" \
        "/dev/shm" \
        "nosuid" \
        "l1-server,l1-workstation"
}

audit_1_1_2_2_4() {
    audit_mount_option \
        "1.1.2.2.4" \
        "Ensure noexec option set on /dev/shm partition" \
        "/dev/shm" \
        "noexec" \
        "l1-server,l1-workstation"
}

audit_1_1_2_3_1() {
    audit_mount_point_exists \
        "1.1.2.3.1" \
        "Ensure separate partition exists for /home" \
        "/home" \
        "l2-server,l2-workstation"
}

audit_1_1_2_3_2() {
    audit_mount_option \
        "1.1.2.3.2" \
        "Ensure nodev option set on /home partition" \
        "/home" \
        "nodev" \
        "l1-server,l1-workstation"
}

audit_1_1_2_3_3() {
    audit_mount_option \
        "1.1.2.3.3" \
        "Ensure nosuid option set on /home partition" \
        "/home" \
        "nosuid" \
        "l1-server,l1-workstation"
}

audit_1_1_2_4_1() {
    audit_mount_point_exists \
        "1.1.2.4.1" \
        "Ensure separate partition exists for /var" \
        "/var" \
        "l2-server,l2-workstation"
}

audit_1_1_2_4_2() {
    audit_mount_option \
        "1.1.2.4.2" \
        "Ensure nodev option set on /var partition" \
        "/var" \
        "nodev" \
        "l1-server,l1-workstation"
}

audit_1_1_2_4_3() {
    audit_mount_option \
        "1.1.2.4.3" \
        "Ensure nosuid option set on /var partition" \
        "/var" \
        "nosuid" \
        "l1-server,l1-workstation"
}

audit_1_1_2_5_1() {
    audit_mount_point_exists \
        "1.1.2.5.1" \
        "Ensure separate partition exists for /var/tmp" \
        "/var/tmp" \
        "l2-server,l2-workstation"
}

audit_1_1_2_5_2() {
    audit_mount_option \
        "1.1.2.5.2" \
        "Ensure nodev option set on /var/tmp partition" \
        "/var/tmp" \
        "nodev" \
        "l1-server,l1-workstation"
}

audit_1_1_2_5_3() {
    audit_mount_option \
        "1.1.2.5.3" \
        "Ensure nosuid option set on /var/tmp partition" \
        "/var/tmp" \
        "nosuid" \
        "l1-server,l1-workstation"
}

audit_1_1_2_5_4() {
    audit_mount_option \
        "1.1.2.5.4" \
        "Ensure noexec option set on /var/tmp partition" \
        "/var/tmp" \
        "noexec" \
        "l1-server,l1-workstation"
}

audit_1_1_2_6_1() {
    audit_mount_point_exists \
        "1.1.2.6.1" \
        "Ensure separate partition exists for /var/log" \
        "/var/log" \
        "l2-server,l2-workstation"
}

audit_1_1_2_6_2() {
    audit_mount_option \
        "1.1.2.6.2" \
        "Ensure nodev option set on /var/log partition" \
        "/var/log" \
        "nodev" \
        "l1-server,l1-workstation"
}

audit_1_1_2_6_3() {
    audit_mount_option \
        "1.1.2.6.3" \
        "Ensure nosuid option set on /var/log partition" \
        "/var/log" \
        "nosuid" \
        "l1-server,l1-workstation"
}

audit_1_1_2_6_4() {
    audit_mount_option \
        "1.1.2.6.4" \
        "Ensure noexec option set on /var/log partition" \
        "/var/log" \
        "noexec" \
        "l1-server,l1-workstation"
}

audit_1_1_2_7_1() {
    audit_mount_point_exists \
        "1.1.2.7.1" \
        "Ensure separate partition exists for /var/log/audit" \
        "/var/log/audit" \
        "l2-server,l2-workstation"
}

audit_1_1_2_7_2() {
    audit_mount_option \
        "1.1.2.7.2" \
        "Ensure nodev option set on /var/log/audit partition" \
        "/var/log/audit" \
        "nodev" \
        "l1-server,l1-workstation"
}

audit_1_1_2_7_3() {
    audit_mount_option \
        "1.1.2.7.3" \
        "Ensure nosuid option set on /var/log/audit partition" \
        "/var/log/audit" \
        "nosuid" \
        "l1-server,l1-workstation"
}

audit_1_1_2_7_4() {
    audit_mount_option \
        "1.1.2.7.4" \
        "Ensure noexec option set on /var/log/audit partition" \
        "/var/log/audit" \
        "noexec" \
        "l1-server,l1-workstation"
}

path_has_owner_group() {
    path="$1"
    user="$2"
    group="$3"

    [ "$(stat -Lc '%U:%G' "$path" 2>/dev/null)" = "$user:$group" ]
}

path_mode_has_no_bits() {
    path="$1"
    disallowed_mask="$2"
    mode="$(stat -Lc '%a' "$path" 2>/dev/null)" || return 1

    [ $((8#$mode & 8#$disallowed_mask)) -eq 0 ]
}

audit_directory_access() {
    control_id="$1"
    title="$2"
    directory="$3"
    disallowed_mask="$4"
    applicability="$5"

    should_run_control "$control_id" "$applicability" || return 0

    if [ -d "$directory" ] \
        && path_has_owner_group "$directory" "root" "root" \
        && path_mode_has_no_bits "$directory" "$disallowed_mask"; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

find_files_with_bad_access() {
    search_path="$1"
    name_pattern="$2"
    disallowed_mask="$3"

    [ -d "$search_path" ] || return 0

    find -L "$search_path" -mount -xdev -type f -name "$name_pattern" \
        \( ! -user root -o ! -group root -o -perm "/$disallowed_mask" \) \
        -print -quit 2>/dev/null
}

find_apt_source_files_with_bad_access() {
    [ -d /etc/apt/sources.list.d ] || return 0

    find -L /etc/apt/sources.list.d/ -mount -xdev -type f \
        \( -name '*.list' -o -name '*.sources' \) \
        \( ! -user root -o ! -group root -o -perm /133 \) \
        -print -quit 2>/dev/null
}

audit_files_access() {
    control_id="$1"
    title="$2"
    search_path="$3"
    name_pattern="$4"
    disallowed_mask="$5"
    applicability="$6"

    should_run_control "$control_id" "$applicability" || return 0

    if [ -z "$(find_files_with_bad_access "$search_path" "$name_pattern" "$disallowed_mask")" ]; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_1_2_1_1() {
    control_id="1.2.1.1"
    title="Ensure the source.list and .source files use the Signed-By option"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0
    manual_control "$control_id" "$title"
}

audit_1_2_1_2() {
    control_id="1.2.1.2"
    title="Ensure weak dependencies are configured"
    applicability="l2-server,l2-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    recommends="$(apt-config dump 2>/dev/null | grep -E '^APT::Install-Recommends ' | tail -n 1)"
    suggests="$(apt-config dump 2>/dev/null | grep -E '^APT::Install-Suggests ' | tail -n 1)"

    if [ "$recommends" = 'APT::Install-Recommends "0";' ] \
        && [ "$suggests" = 'APT::Install-Suggests "0";' ]; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_1_2_1_3() {
    control_id="1.2.1.3"
    title="Ensure access to gpg key files are configured"
    applicability="l1-server,l2-server"

    should_run_control "$control_id" "$applicability" || return 0

    bad_key_files="$(
        find -L /usr/share/keyrings/ /etc/apt/trusted.gpg.d/ \
            -mount -xdev -type f \( ! -user root -o ! -group root -o -perm /133 \) \
            -name '*gpg' -print -quit 2>/dev/null
    )"
    bad_source_files="$(find_apt_source_files_with_bad_access)"

    if [ -z "$bad_key_files" ] && [ -z "$bad_source_files" ]; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_1_2_1_4() {
    audit_directory_access \
        "1.2.1.4" \
        "Ensure access to /etc/apt/trusted.gpg.d directory is configured" \
        "/etc/apt/trusted.gpg.d" \
        "7022" \
        "l1-server,l2-server"
}

audit_1_2_1_5() {
    audit_directory_access \
        "1.2.1.5" \
        "Ensure access to /etc/apt/auth.conf.d directory is configured" \
        "/etc/apt/auth.conf.d" \
        "7022" \
        "l1-server,l2-server"
}

audit_1_2_1_6() {
    audit_files_access \
        "1.2.1.6" \
        "Ensure access to files in the /etc/apt/auth.conf.d/ directory is configured" \
        "/etc/apt/auth.conf.d" \
        "*" \
        "137" \
        "l1-server,l1-workstation"
}

audit_1_2_1_7() {
    audit_directory_access \
        "1.2.1.7" \
        "Ensure access to /usr/share/keyrings directory is configured" \
        "/usr/share/keyrings" \
        "7022" \
        "l1-server,l2-server"
}

audit_1_2_1_8() {
    audit_directory_access \
        "1.2.1.8" \
        "Ensure access to /etc/apt/sources.list.d directory is configured" \
        "/etc/apt/sources.list.d" \
        "7022" \
        "l1-server,l2-server"
}

audit_1_2_1_9() {
    audit_files_access \
        "1.2.1.9" \
        "Ensure access to files in /etc/apt/sources.list.d are configured" \
        "/etc/apt/sources.list.d" \
        "*" \
        "133" \
        "l1-server,l2-server"
}

audit_1_2_2_1() {
    control_id="1.2.2.1"
    title="Ensure updates, patches, and additional security software are installed"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0
    manual_control "$control_id" "$title"
}

package_installed() {
    package_name="$1"

    dpkg-query -s "$package_name" >/dev/null 2>&1
}

apparmor_packages_installed() {
    package_installed "apparmor" && package_installed "apparmor-utils"
}

audit_1_3_1_1() {
    control_id="1.3.1.1"
    title="Ensure apparmor packages are installed"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if apparmor_packages_installed; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_1_3_1_2() {
    control_id="1.3.1.2"
    title="Ensure AppArmor is enabled"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if ! apparmor_packages_installed; then
        na_control "$control_id" "$title"
    elif grep "^[[:space:]]*linux" /boot/grub/grub.cfg 2>/dev/null | grep -q "apparmor=0"; then
        fail_control "$control_id" "$title"
    else
        pass_control "$control_id" "$title"
    fi
}

audit_1_3_1_3() {
    control_id="1.3.1.3"
    title="Ensure all AppArmor Profiles are enforcing"
    applicability="l2-server,l2-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if ! apparmor_packages_installed; then
        na_control "$control_id" "$title"
        return 0
    fi

    if ! command -v apparmor_status >/dev/null 2>&1; then
        fail_control "$control_id" "$title"
        return 0
    fi

    apparmor_output="$(apparmor_status 2>/dev/null)"
    loaded_profiles="$(printf '%s\n' "$apparmor_output" | awk '/profiles are loaded\./ {print $1; exit}')"
    complain_profiles="$(printf '%s\n' "$apparmor_output" | awk '/profiles are in complain mode\./ {print $1; exit}')"
    unconfined_processes="$(printf '%s\n' "$apparmor_output" | awk '/processes are unconfined but have a profile defined\./ {print $1; exit}')"

    if [ "${loaded_profiles:-0}" -gt 0 ] \
        && [ "${complain_profiles:-1}" -eq 0 ] \
        && [ "${unconfined_processes:-1}" -eq 0 ]; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

sysctl_current_value_is() {
    parameter="$1"
    expected="$2"

    [ "$(sysctl -n "$parameter" 2>/dev/null)" = "$expected" ]
}

sysctl_persistent_value_is() {
    parameter="$1"
    expected="$2"
    escaped_parameter="$(printf '%s' "$parameter" | sed 's/\./\\./g')"
    systemd_sysctl="$(readlink -e /lib/systemd/systemd-sysctl 2>/dev/null || readlink -e /usr/lib/systemd/systemd-sysctl 2>/dev/null)"

    if [ -f /etc/default/ufw ]; then
        ufw_sysctl_file="$(awk -F= '/^[[:space:]]*IPT_SYSCTL=/ {print $2}' /etc/default/ufw | tr -d '"'\''')"
        if [ -n "$ufw_sysctl_file" ] && [ -f "$ufw_sysctl_file" ]; then
            ufw_value="$(grep -Psoi "^\h*${escaped_parameter}\h*=\h*\H+\b" "$ufw_sysctl_file" 2>/dev/null | tail -n 1 | cut -d= -f2 | xargs)"
            [ "$ufw_value" = "$expected" ] && return 0
        fi
    fi

    [ -n "$systemd_sysctl" ] || return 1

    while IFS= read -r config_file; do
        config_file="${config_file//# /}"
        [ -f "$config_file" ] || continue
        config_value="$(grep -Psoi "^\h*${escaped_parameter}\h*=\h*\H+\b" "$config_file" 2>/dev/null | tail -n 1 | cut -d= -f2 | xargs)"
        [ -n "$config_value" ] || continue
        [ "$config_value" = "$expected" ] && return 0
        return 1
    done < <("$systemd_sysctl" --cat-config 2>/dev/null | tac | grep -Psoi '^\h*#\h*\/[^#\n\r\h]+\.conf\b')

    return 1
}

audit_1_3_1_4() {
    control_id="1.3.1.4"
    title="Ensure apparmor_restrict_unprivileged_unconfined is enabled"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if ! apparmor_packages_installed; then
        na_control "$control_id" "$title"
    elif sysctl_current_value_is "kernel.apparmor_restrict_unprivileged_unconfined" "1" \
        && sysctl_persistent_value_is "kernel.apparmor_restrict_unprivileged_unconfined" "1"; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_1_4_1() {
    control_id="1.4.1"
    title="Ensure bootloader password is set"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if grep -q "^set superusers" /boot/grub/grub.cfg 2>/dev/null \
        && awk -F. '/^[[:space:]]*password/ {print $1"."$2"."$3}' /boot/grub/grub.cfg 2>/dev/null \
            | grep -q '^password_pbkdf2 [^[:space:]]\+ grub\.pbkdf2\.sha512$'; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_1_4_2() {
    control_id="1.4.2"
    title="Ensure access to bootloader config is configured"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if [ -f /boot/grub/grub.cfg ] \
        && path_has_owner_group "/boot/grub/grub.cfg" "root" "root" \
        && path_mode_has_no_bits "/boot/grub/grub.cfg" "7177"; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

sysctl_persistent_value_matches() {
    parameter="$1"
    expected_regex="$2"
    escaped_parameter="$(printf '%s' "$parameter" | sed 's#\.#(\\.|/)#g')"
    systemd_sysctl="$(readlink -e /lib/systemd/systemd-sysctl 2>/dev/null || readlink -e /usr/lib/systemd/systemd-sysctl 2>/dev/null)"
    files=()

    if [ -f /etc/default/ufw ]; then
        ufw_sysctl_file="$(awk -F= '/^[[:space:]]*IPT_SYSCTL=/ {print $2}' /etc/default/ufw | tr -d '"'\''')"
        ufw_sysctl_file="$(readlink -e "$ufw_sysctl_file" 2>/dev/null)"
        [ -n "$ufw_sysctl_file" ] && files+=("$ufw_sysctl_file")
    fi

    [ -f /etc/sysctl.conf ] && files+=("/etc/sysctl.conf")

    if [ -n "$systemd_sysctl" ]; then
        while IFS= read -r config_file; do
            config_file="$(readlink -e "${config_file//# /}" 2>/dev/null)"
            [ -n "$config_file" ] || continue
            printf '%s\n' "${files[@]}" | grep -Fxq "$config_file" || files+=("$config_file")
        done < <("$systemd_sysctl" --cat-config 2>/dev/null | tac | grep -Psoi '^\h*#\h*\/[^#\n\r\h]+\.conf\b')
    fi

    for config_file in "${files[@]}"; do
        config_value="$(grep -Psoi "^\h*${escaped_parameter}\h*=\h*\H+\b" "$config_file" 2>/dev/null | tail -n 1 | cut -d= -f2 | xargs)"
        [ -n "$config_value" ] || continue
        printf '%s\n' "$config_value" | grep -Eq "^(${expected_regex})$"
        return $?
    done

    return 1
}

audit_sysctl_parameter() {
    control_id="$1"
    title="$2"
    parameter="$3"
    expected_regex="$4"
    applicability="$5"

    should_run_control "$control_id" "$applicability" || return 0

    current_value="$(sysctl -n "$parameter" 2>/dev/null)"

    if printf '%s\n' "$current_value" | grep -Eq "^(${expected_regex})$" \
        && sysctl_persistent_value_matches "$parameter" "$expected_regex"; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_1_5_1() {
    audit_sysctl_parameter \
        "1.5.1" \
        "Ensure fs.protected_hardlinks is configured" \
        "fs.protected_hardlinks" \
        "1" \
        "l1-server,l1-workstation"
}

audit_1_5_2() {
    audit_sysctl_parameter \
        "1.5.2" \
        "Ensure fs.protected_symlinks is configured" \
        "fs.protected_symlinks" \
        "1" \
        "l2-server,l2-workstation"
}

audit_1_5_3() {
    audit_sysctl_parameter \
        "1.5.3" \
        "Ensure kernel.yama.ptrace_scope is configured" \
        "kernel.yama.ptrace_scope" \
        "[123]" \
        "l1-server,l1-workstation"
}

audit_1_5_4() {
    audit_sysctl_parameter \
        "1.5.4" \
        "Ensure fs.suid_dumpable is configured" \
        "fs.suid_dumpable" \
        "0" \
        "l1-server,l1-workstation"
}

audit_1_5_5() {
    audit_sysctl_parameter \
        "1.5.5" \
        "Ensure kernel.dmesg_restrict is configured" \
        "kernel.dmesg_restrict" \
        "1" \
        "l1-server,l1-workstation"
}

audit_1_5_6() {
    control_id="1.5.6"
    title="Ensure prelink is not installed"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if package_installed "prelink"; then
        fail_control "$control_id" "$title"
    else
        pass_control "$control_id" "$title"
    fi
}

audit_1_5_7() {
    control_id="1.5.7"
    title="Ensure Automatic Error Reporting is configured"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if package_installed "apport" \
        && grep -Psiq -- '^\h*enabled\h*=\h*[^0]\b' /etc/default/apport 2>/dev/null; then
        fail_control "$control_id" "$title"
    elif systemctl is-active apport.service 2>/dev/null | grep -q '^active'; then
        fail_control "$control_id" "$title"
    else
        pass_control "$control_id" "$title"
    fi
}

audit_1_5_8() {
    audit_sysctl_parameter \
        "1.5.8" \
        "Ensure kernel.kptr_restrict is configured" \
        "kernel.kptr_restrict" \
        "[12]" \
        "l1-server,l1-workstation"
}

audit_1_5_9() {
    audit_sysctl_parameter \
        "1.5.9" \
        "Ensure kernel.randomize_va_space is configured" \
        "kernel.randomize_va_space" \
        "2" \
        "l1-server,l1-workstation"
}

coredump_option_effective_value() {
    option="$1"
    analyze_cmd="$(readlink -e /bin/systemd-analyze 2>/dev/null || readlink -e /usr/bin/systemd-analyze 2>/dev/null)"
    conf_file="systemd/coredump.conf"
    block="Coredump"

    if [ -n "$analyze_cmd" ]; then
        while IFS= read -r config_file; do
            config_file="${config_file//# /}"
            value="$(awk '/\['"$block"'\]/{a=1;next}/\[/{a=0}a' "$config_file" 2>/dev/null \
                | grep -Poi "^\h*${option}\h*=\h*\H+\b" \
                | tail -n 1 \
                | cut -d= -f2 \
                | xargs)"
            [ -n "$value" ] && { printf '%s\n' "$value"; return 0; }
        done < <("$analyze_cmd" cat-config "$conf_file" 2>/dev/null | tac | grep -Pio '^\h*#\h*\/[^#\n\r\h]+\.conf\b')
    fi

    config_file="$(readlink -e /etc/"$conf_file" 2>/dev/null || readlink -e /usr/lib/"$conf_file" 2>/dev/null)"
    [ -n "$config_file" ] || return 1

    awk '/\['"$block"'\]/{a=1;next}/\[/{a=0}a' "$config_file" 2>/dev/null \
        | grep -Poim 1 "^(\h*#)?\h*${option}\h*=\h*\H+\b" \
        | sed 's/#//g' \
        | cut -d= -f2 \
        | xargs
}

audit_coredump_option() {
    control_id="$1"
    title="$2"
    option="$3"
    expected="$4"
    applicability="$5"

    should_run_control "$control_id" "$applicability" || return 0

    if ! package_installed "systemd-coredump"; then
        pass_control "$control_id" "$title"
        return 0
    fi

    if [ "$(coredump_option_effective_value "$option")" = "$expected" ]; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_1_5_11() {
    audit_coredump_option \
        "1.5.11" \
        "Ensure systemd-coredump ProcessSizeMax is configured" \
        "ProcessSizeMax" \
        "0" \
        "l1-server,l1-workstation"
}

audit_1_5_12() {
    audit_coredump_option \
        "1.5.12" \
        "Ensure systemd-coredump Storage is configured" \
        "Storage" \
        "none" \
        "l1-server,l1-workstation"
}

os_id() {
    awk -F= '/^ID=/ {gsub(/"/, "", $2); print $2; exit}' /etc/os-release 2>/dev/null
}

file_contains_os_disclosure() {
    file="$1"
    id="$(os_id)"

    [ -f "$file" ] || return 1

    if [ -n "$id" ]; then
        grep -Psiq -- "(\\\\v|\\\\r|\\\\m|\\\\s|\\b${id}\\b)" "$file" 2>/dev/null
    else
        grep -Psiq -- "(\\\\v|\\\\r|\\\\m|\\\\s)" "$file" 2>/dev/null
    fi
}

paths_contain_os_disclosure() {
    for path in "$@"; do
        if [ -f "$path" ] && file_contains_os_disclosure "$path"; then
            return 0
        fi
    done

    return 1
}

path_access_0644_or_more_restrictive() {
    path="$1"

    [ -e "$path" ] \
        && path_has_owner_group "$path" "root" "root" \
        && path_mode_has_no_bits "$path" "7133"
}

paths_access_0644_or_more_restrictive() {
    for path in "$@"; do
        [ -e "$path" ] || continue
        path_access_0644_or_more_restrictive "$path" || return 1
    done

    return 0
}

audit_paths_no_os_disclosure() {
    control_id="$1"
    title="$2"
    applicability="$3"
    shift 3

    should_run_control "$control_id" "$applicability" || return 0

    if paths_contain_os_disclosure "$@"; then
        fail_control "$control_id" "$title"
    else
        pass_control "$control_id" "$title"
    fi
}

audit_paths_access_0644() {
    control_id="$1"
    title="$2"
    applicability="$3"
    shift 3

    should_run_control "$control_id" "$applicability" || return 0

    if paths_access_0644_or_more_restrictive "$@"; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

motd_paths() {
    printf '%s\0' \
        /etc/motd \
        /run/motd \
        /usr/lib/motd

    find /etc/motd.d/ /run/motd.d/ /usr/lib/motd.d/ /etc/update-motd.d/ \
        -maxdepth 1 -type f -print0 2>/dev/null
}

issue_paths() {
    printf '%s\0' /etc/issue
    find /usr/lib/issue.d/ /etc/issue.d/ /run/issue.d/ \
        -maxdepth 1 -type f -print0 2>/dev/null
}

pam_motd_paths() {
    grep -hPo 'motd=\K"[^"]+"|motd=\K'\''[^'\'']+'\''|motd=\K\S+' /etc/pam.d/* 2>/dev/null \
        | sed "s/^['\"]//;s/['\"]$//" \
        | sort -u
}

sshd_banner_path() {
    command -v sshd >/dev/null 2>&1 || return 1
    sshd -T 2>/dev/null | awk '$1 == "banner" && $2 != "none" {print $2; exit}'
}

audit_1_6_1() {
    control_id="1.6.1"
    title="Ensure /etc/motd is configured"
    applicability="l1-server,l1-workstation"
    paths=()

    should_run_control "$control_id" "$applicability" || return 0

    while IFS= read -r -d '' path; do
        paths+=("$path")
    done < <(motd_paths)

    if paths_contain_os_disclosure "${paths[@]}"; then
        fail_control "$control_id" "$title"
    else
        pass_control "$control_id" "$title"
    fi
}

audit_1_6_2() {
    control_id="1.6.2"
    title="Ensure /etc/issue is configured"
    applicability="l1-server,l1-workstation"
    paths=()

    should_run_control "$control_id" "$applicability" || return 0

    while IFS= read -r -d '' path; do
        paths+=("$path")
    done < <(issue_paths)

    if paths_contain_os_disclosure "${paths[@]}"; then
        fail_control "$control_id" "$title"
    else
        pass_control "$control_id" "$title"
    fi
}

audit_1_6_3() {
    audit_paths_no_os_disclosure \
        "1.6.3" \
        "Ensure /etc/issue.net is configured" \
        "l1-server,l1-workstation" \
        "/etc/issue.net"
}

audit_1_6_4() {
    control_id="1.6.4"
    title="Ensure pam_motd is configured"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    while IFS= read -r motd_path; do
        [ -r "$motd_path" ] || continue
        if file_contains_os_disclosure "$motd_path"; then
            fail_control "$control_id" "$title"
            return 0
        fi
    done < <(pam_motd_paths)

    pass_control "$control_id" "$title"
}

audit_1_6_5() {
    control_id="1.6.5"
    title="Ensure sshd warning Banner is configured"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    banner_path="$(sshd_banner_path)"

    if [ -n "$banner_path" ] && [ -f "$banner_path" ] && ! file_contains_os_disclosure "$banner_path"; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_1_6_6() {
    control_id="1.6.6"
    title="Ensure access to /etc/motd is configured"
    applicability="l1-server,l1-workstation"
    paths=()

    should_run_control "$control_id" "$applicability" || return 0

    while IFS= read -r -d '' path; do
        paths+=("$path")
    done < <(motd_paths)

    if paths_access_0644_or_more_restrictive "${paths[@]}"; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_1_6_7() {
    control_id="1.6.7"
    title="Ensure access to /etc/issue is configured"
    applicability="l1-server,l1-workstation"
    paths=()

    should_run_control "$control_id" "$applicability" || return 0

    while IFS= read -r -d '' path; do
        paths+=("$path")
    done < <(issue_paths)

    if paths_access_0644_or_more_restrictive "${paths[@]}"; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_1_6_8() {
    audit_paths_access_0644 \
        "1.6.8" \
        "Ensure access to /etc/issue.net is configured" \
        "l1-server,l1-workstation" \
        "/etc/issue.net"
}

audit_1_6_9() {
    control_id="1.6.9"
    title="Ensure access to pam_motd file is configured"
    applicability="l1-server,l1-workstation"
    paths=()

    should_run_control "$control_id" "$applicability" || return 0

    while IFS= read -r path; do
        paths+=("$path")
    done < <(pam_motd_paths)

    if paths_access_0644_or_more_restrictive "${paths[@]}"; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_1_6_10() {
    control_id="1.6.10"
    title="Ensure access to sshd warning banner is configured"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    banner_path="$(sshd_banner_path)"

    if [ -z "$banner_path" ]; then
        na_control "$control_id" "$title"
    elif path_access_0644_or_more_restrictive "$banner_path"; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

gsettings_available() {
    command -v gsettings >/dev/null 2>&1
}

gdm_available() {
    package_installed "gdm3" || package_installed "gdm"
}

gsettings_get_value() {
    schema="$1"
    key="$2"

    gsettings get "$schema" "$key" 2>/dev/null
}

gsettings_writable_value() {
    schema="$1"
    key="$2"

    gsettings writable "$schema" "$key" 2>/dev/null
}

gdm_xdmcp_enabled() {
    for file in /etc/gdm3/custom.conf /etc/gdm3/daemon.conf /etc/gdm/custom.conf /etc/gdm/daemon.conf; do
        [ -f "$file" ] || continue
        awk '/\[xdmcp\]/{f=1;next}/\[/{f=0}f && /^\s*Enable\s*=\s*true/ {found=1} END {exit !found}' "$file" && return 0
    done

    return 1
}

audit_gsettings_boolean_locked_value() {
    control_id="$1"
    title="$2"
    applicability="$3"
    schema="$4"
    key="$5"
    expected="$6"

    should_run_control "$control_id" "$applicability" || return 0

    if ! gdm_available || ! gsettings_available; then
        na_control "$control_id" "$title"
    elif [ "$(gsettings_writable_value "$schema" "$key")" = "false" ] \
        && [ "$(gsettings_get_value "$schema" "$key")" = "$expected" ]; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_1_7_1() {
    control_id="1.7.1"
    title="Ensure GDM login banner is configured"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if ! gdm_available || ! gsettings_available; then
        na_control "$control_id" "$title"
    elif [ "$(gsettings_writable_value org.gnome.login-screen banner-message-enable)" = "false" ] \
        && [ "$(gsettings_writable_value org.gnome.login-screen banner-message-text)" = "false" ] \
        && [ "$(gsettings_get_value org.gnome.login-screen banner-message-enable)" = "true" ] \
        && [ -n "$(gsettings_get_value org.gnome.login-screen banner-message-text | sed \"s/^'//;s/'$//\")" ]; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_1_7_2() {
    audit_gsettings_boolean_locked_value \
        "1.7.2" \
        "Ensure GDM disable-user-list is configured" \
        "l1-server,l1-workstation" \
        "org.gnome.login-screen" \
        "disable-user-list" \
        "true"
}

audit_1_7_3() {
    control_id="1.7.3"
    title="Ensure GDM screen lock is configured"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if ! gdm_available || ! gsettings_available; then
        na_control "$control_id" "$title"
        return 0
    fi

    idle_delay="$(gsettings_get_value org.gnome.desktop.session idle-delay | awk '{print $2}')"
    lock_delay="$(gsettings_get_value org.gnome.desktop.screensaver lock-delay | awk '{print $2}')"

    if [ "$(gsettings_writable_value org.gnome.desktop.session idle-delay)" = "false" ] \
        && [ "$(gsettings_writable_value org.gnome.desktop.screensaver lock-delay)" = "false" ] \
        && [ "$idle_delay" -gt 0 ] 2>/dev/null \
        && [ "$idle_delay" -le 900 ] 2>/dev/null \
        && [ "$lock_delay" -le 5 ] 2>/dev/null; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_1_7_4() {
    control_id="1.7.4"
    title="Ensure GDM automount is configured"
    applicability="l1-server,l2-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if ! gdm_available || ! gsettings_available; then
        na_control "$control_id" "$title"
    elif [ "$(gsettings_writable_value org.gnome.desktop.media-handling automount)" = "false" ] \
        && [ "$(gsettings_writable_value org.gnome.desktop.media-handling automount-open)" = "false" ] \
        && [ "$(gsettings_get_value org.gnome.desktop.media-handling automount)" = "false" ] \
        && [ "$(gsettings_get_value org.gnome.desktop.media-handling automount-open)" = "false" ]; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_1_7_5() {
    audit_gsettings_boolean_locked_value \
        "1.7.5" \
        "Ensure GDM autorun-never is configured" \
        "l1-server,l1-workstation" \
        "org.gnome.desktop.media-handling" \
        "autorun-never" \
        "true"
}

audit_1_7_6() {
    control_id="1.7.6"
    title="Ensure XDMCP is not enabled"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if ! gdm_available; then
        na_control "$control_id" "$title"
        return 0
    fi

    if gdm_xdmcp_enabled; then
        fail_control "$control_id" "$title"
    else
        pass_control "$control_id" "$title"
    fi
}

audit_1_7_7() {
    control_id="1.7.7"
    title="Ensure Xwayland is configured"
    applicability="l2-server,l2-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if ! gdm_available; then
        na_control "$control_id" "$title"
    elif sed -n '/\[daemon\]/,/\[/p' /etc/gdm/custom.conf 2>/dev/null | grep -Psiq '^\h*waylandenable\h*=\h*false\b'; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

packages_installed() {
    for package_name in "$@"; do
        package_installed "$package_name" && return 0
    done

    return 1
}

installed_package_matches() {
    pattern="$1"

    dpkg-query -W -f='${binary:Package}\n' 2>/dev/null | grep -Piq -- "$pattern"
}

systemd_units_enabled_or_active() {
    for unit in "$@"; do
        systemctl is-enabled "$unit" 2>/dev/null | grep -q 'enabled' && return 0
        systemctl is-active "$unit" 2>/dev/null | grep -q '^active' && return 0
    done

    return 1
}

audit_package_services_not_in_use() {
    control_id="$1"
    title="$2"
    applicability="$3"
    packages="$4"
    units="$5"

    should_run_control "$control_id" "$applicability" || return 0

    read -r -a package_array <<< "$packages"
    read -r -a unit_array <<< "$units"

    if ! packages_installed "${package_array[@]}"; then
        pass_control "$control_id" "$title"
    elif ! systemd_units_enabled_or_active "${unit_array[@]}"; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

mta_listening_non_loopback() {
    ports="25 465 587"

    for port in $ports; do
        if ss -plntu 2>/dev/null | grep -P -- ":${port}\b" | grep -Pvq -- "\h+(127\.0\.0\.1|\[?::1\]?):${port}\b"; then
            return 0
        fi
    done

    if command -v postconf >/dev/null 2>&1; then
        interfaces="$(postconf -n inet_interfaces 2>/dev/null)"
    elif command -v exim >/dev/null 2>&1; then
        interfaces="$(exim -bP local_interfaces 2>/dev/null)"
    elif command -v sendmail >/dev/null 2>&1 && [ -f /etc/mail/sendmail.cf ]; then
        interfaces="$(grep -i "O DaemonPortOptions=" /etc/mail/sendmail.cf | grep -oP '(?<=Addr=)[^,+]+' | grep -v '^127\.0\.0\.1$')"
    else
        interfaces=""
    fi

    [ -z "$interfaces" ] && return 1

    if grep -Pqi '\ball\b' <<< "$interfaces"; then
        return 0
    fi

    if ! grep -Pqi '(inet_interfaces\h*=\h*)?(0\.0\.0\.0|::1|loopback-only)' <<< "$interfaces"; then
        return 0
    fi

    return 1
}

audit_2_1_1() {
    audit_package_services_not_in_use \
        "2.1.1" \
        "Ensure autofs services are not in use" \
        "l1-server,l2-workstation" \
        "autofs" \
        "autofs.service"
}

audit_2_1_2() {
    control_id="2.1.2"
    title="Ensure mail transfer agents are configured for local-only mode"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if mta_listening_non_loopback; then
        fail_control "$control_id" "$title"
    else
        pass_control "$control_id" "$title"
    fi
}

audit_2_1_3() {
    audit_package_services_not_in_use \
        "2.1.3" \
        "Ensure avahi daemon services are not in use" \
        "l1-server,l2-workstation" \
        "avahi-daemon" \
        "avahi-daemon.socket avahi-daemon.service"
}

audit_2_1_4() {
    control_id="2.1.4"
    title="Ensure only approved services are listening on a network interface"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0
    manual_control "$control_id" "$title"
}

audit_2_1_5() {
    control_id="2.1.5"
    title="Ensure dhcp server services are not in use"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if ! installed_package_matches '^kea'; then
        pass_control "$control_id" "$title"
    elif ! systemd_units_enabled_or_active kea-dhcp-ddns-server.service kea-dhcp4-server.service kea-dhcp6-server.service; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_2_1_6() {
    control_id="2.1.6"
    title="Ensure web server services are not in use"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    apache_bad=0
    nginx_bad=0

    if package_installed "apache2" && systemd_units_enabled_or_active apache2.socket apache2.service; then
        apache_bad=1
    fi

    if package_installed "nginx" && systemd_units_enabled_or_active nginx.service; then
        nginx_bad=1
    fi

    if ! package_installed "apache2" && ! package_installed "nginx"; then
        pass_control "$control_id" "$title"
    elif [ "$apache_bad" -eq 0 ] && [ "$nginx_bad" -eq 0 ]; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_2_1_7() {
    audit_package_services_not_in_use "2.1.7" "Ensure dns server services are not in use" "l1-server,l1-workstation" "bind9" "named.service"
}

audit_2_1_8() {
    audit_package_services_not_in_use "2.1.8" "Ensure ftp server services are not in use" "l1-server,l1-workstation" "vsftpd" "vsftpd.service"
}

audit_2_1_9() {
    audit_package_services_not_in_use "2.1.9" "Ensure dnsmasq services are not in use" "l1-server,l1-workstation" "dnsmasq" "dnsmasq.service"
}

audit_2_1_10() {
    audit_package_services_not_in_use "2.1.10" "Ensure ldap server services are not in use" "l1-server,l1-workstation" "slapd" "slapd.service"
}

audit_2_1_11() {
    audit_package_services_not_in_use \
        "2.1.11" \
        "Ensure message access server services are not in use" \
        "l1-server,l1-workstation" \
        "dovecot-imapd dovecot-pop3d" \
        "dovecot.socket dovecot.service"
}

audit_2_1_12() {
    audit_package_services_not_in_use "2.1.12" "Ensure network file system services are not in use" "l1-server,l1-workstation" "nfs-kernel-server" "nfs-server.service"
}

audit_2_1_13() {
    audit_package_services_not_in_use "2.1.13" "Ensure nis server services are not in use" "l1-server,l1-workstation" "ypserv" "ypserv.service"
}

audit_2_1_14() {
    audit_package_services_not_in_use "2.1.14" "Ensure print server services are not in use" "l1-server,l2-workstation" "cups" "cups.socket cups.service"
}

audit_2_1_15() {
    audit_package_services_not_in_use "2.1.15" "Ensure rpcbind services are not in use" "l1-server,l1-workstation" "rpcbind" "rpcbind.socket rpcbind.service"
}

audit_2_1_16() {
    audit_package_services_not_in_use "2.1.16" "Ensure rsync services are not in use" "l1-server,l1-workstation" "rsync" "rsync.service"
}

audit_2_1_17() {
    audit_package_services_not_in_use "2.1.17" "Ensure samba file server services are not in use" "l1-server,l1-workstation" "samba" "smbd.service"
}

audit_2_1_18() {
    audit_package_services_not_in_use "2.1.18" "Ensure snmp services are not in use" "l1-server,l1-workstation" "snmpd" "snmpd.service"
}

audit_2_1_19() {
    control_id="2.1.19"
    title="Ensure telnet server services are not in use"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if ! installed_package_matches '^telnetd|^telnetd-ssl'; then
        pass_control "$control_id" "$title"
    elif ! systemd_units_enabled_or_active inetutils-inetd.service; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_2_1_20() {
    audit_package_services_not_in_use "2.1.20" "Ensure tftp server services are not in use" "l1-server,l1-workstation" "tftpd-hpa" "tftpd-hpa.service"
}

audit_2_1_21() {
    audit_package_services_not_in_use "2.1.21" "Ensure web proxy server services are not in use" "l1-server,l1-workstation" "squid" "squid.service"
}

audit_2_1_22() {
    audit_package_services_not_in_use "2.1.22" "Ensure xinetd services are not in use" "l1-server,l1-workstation" "xinetd" "xinetd.service"
}

audit_2_1_23() {
    control_id="2.1.23"
    title="Ensure X window server services are not in use"
    applicability="l2-server"

    should_run_control "$control_id" "$applicability" || return 0

    if package_installed "xserver-common"; then
        fail_control "$control_id" "$title"
    else
        pass_control "$control_id" "$title"
    fi
}

audit_packages_not_installed() {
    control_id="$1"
    title="$2"
    applicability="$3"
    shift 3

    should_run_control "$control_id" "$applicability" || return 0

    if packages_installed "$@"; then
        fail_control "$control_id" "$title"
    else
        pass_control "$control_id" "$title"
    fi
}

audit_2_2_1() {
    audit_packages_not_installed \
        "2.2.1" \
        "Ensure nis client is not installed" \
        "l1-server,l1-workstation" \
        "nis"
}

audit_2_2_2() {
    audit_packages_not_installed \
        "2.2.2" \
        "Ensure rsh client is not installed" \
        "l1-server,l1-workstation" \
        "rsh-client"
}

audit_2_2_3() {
    audit_packages_not_installed \
        "2.2.3" \
        "Ensure talk client is not installed" \
        "l1-server,l1-workstation" \
        "talk"
}

audit_2_2_4() {
    audit_packages_not_installed \
        "2.2.4" \
        "Ensure telnet client is not installed" \
        "l1-server,l1-workstation" \
        "telnet" \
        "inetutils-telnet"
}

audit_2_2_5() {
    audit_packages_not_installed \
        "2.2.5" \
        "Ensure ldap client is not installed" \
        "l1-server,l1-workstation" \
        "ldap-utils"
}

audit_2_2_6() {
    control_id="2.2.6"
    title="Ensure ftp client is not installed"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if installed_package_matches '^(ftp|tnftp)'; then
        fail_control "$control_id" "$title"
    else
        pass_control "$control_id" "$title"
    fi
}

unit_enabled_and_active() {
    unit="$1"

    systemctl is-enabled "$unit" 2>/dev/null | grep -q '^enabled' \
        && systemctl is-active "$unit" 2>/dev/null | grep -q '^active'
}

unit_enabled_or_active() {
    unit="$1"

    systemctl is-enabled "$unit" 2>/dev/null | grep -q 'enabled' \
        || systemctl is-active "$unit" 2>/dev/null | grep -q '^active'
}

timesyncd_in_use() {
    unit_enabled_or_active "systemd-timesyncd.service"
}

chrony_in_use() {
    unit_enabled_or_active "chrony.service"
}

audit_2_3_1_1() {
    control_id="2.3.1.1"
    title="Ensure a single time synchronization daemon is in use"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    timesyncd=0
    chrony=0

    timesyncd_in_use && timesyncd=1
    chrony_in_use && chrony=1

    if [ "$timesyncd" -ne "$chrony" ]; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

timesyncd_option_set() {
    option="$1"
    analyze_cmd="$(readlink -e /bin/systemd-analyze 2>/dev/null || readlink -e /usr/bin/systemd-analyze 2>/dev/null)"

    [ -n "$analyze_cmd" ] || return 1

    while IFS= read -r config_file; do
        config_file="${config_file//# /}"
        grep -PHs -- "^\h*${option}\b" "$config_file" 2>/dev/null | tail -n 1 | grep -Pq "=\H+" && return 0
    done < <("$analyze_cmd" cat-config /etc/systemd/timesyncd.conf 2>/dev/null | tac | grep -Pio '^\h*#\h*\/[^#\n\r\h]+\.conf\b')

    return 1
}

audit_2_3_2_1() {
    control_id="2.3.2.1"
    title="Ensure systemd-timesyncd configured with authorized timeserver"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if ! timesyncd_in_use; then
        na_control "$control_id" "$title"
    elif timesyncd_option_set "NTP" || timesyncd_option_set "FallbackNTP"; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_2_3_2_2() {
    control_id="2.3.2.2"
    title="Ensure systemd-timesyncd is enabled and running"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if chrony_in_use; then
        na_control "$control_id" "$title"
    elif unit_enabled_and_active "systemd-timesyncd.service"; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

chrony_config_files() {
    config_files=("/etc/chrony/chrony.conf")

    while IFS= read -r conf_location; do
        if [ -d "$conf_location" ]; then
            find -L "$conf_location" -type f -print 2>/dev/null
        elif [ -f "$(readlink -f "$conf_location" 2>/dev/null)" ]; then
            readlink -f "$conf_location"
        elif grep -Psq '/\*\.([^#/\n\r]+)?\h*$' <<< "$conf_location"; then
            dir_name="$(dirname "$conf_location")"
            base_name="$(basename "$conf_location")"
            find -L "$dir_name" -type f -name "$base_name" -print 2>/dev/null
        fi
    done < <(awk '$1~/^\s*(confdir|sourcedir)$/ {print $2}' "${config_files[@]}" 2>/dev/null)

    printf '%s\n' "${config_files[@]}"
}

chrony_has_time_source() {
    while IFS= read -r config_file; do
        [ -f "$config_file" ] || continue
        grep -Psiq '^\h*(server|pool)(\h+|\h*:\h*)[^#\n\r]+\b' "$config_file" && return 0
    done < <(chrony_config_files | sort -u)

    return 1
}

audit_2_3_3_1() {
    control_id="2.3.3.1"
    title="Ensure chrony is configured"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if ! chrony_in_use; then
        na_control "$control_id" "$title"
    elif chrony_has_time_source; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_2_3_3_2() {
    control_id="2.3.3.2"
    title="Ensure chrony is running as user _chrony"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if ! chrony_in_use; then
        na_control "$control_id" "$title"
    elif ps -ef | awk '(/[c]hronyd/ && $1!="_chrony") { found=1 } END { exit !found }'; then
        fail_control "$control_id" "$title"
    else
        pass_control "$control_id" "$title"
    fi
}

audit_2_3_3_3() {
    control_id="2.3.3.3"
    title="Ensure chrony is enabled and running"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if timesyncd_in_use; then
        na_control "$control_id" "$title"
    elif unit_enabled_and_active "chrony.service"; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

cron_unit_name() {
    systemctl list-unit-files 2>/dev/null | awk '$1~/^crond?\.service$/ {print $1; exit}'
}

cron_installed() {
    [ -n "$(cron_unit_name)" ] || package_installed "cron"
}

audit_cron_file_access_0600() {
    control_id="$1"
    title="$2"
    path="$3"
    missing_ok="$4"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if ! cron_installed; then
        na_control "$control_id" "$title"
    elif [ ! -e "$path" ] && [ "$missing_ok" = "missing-ok" ]; then
        pass_control "$control_id" "$title"
    elif [ -e "$path" ] \
        && path_has_owner_group "$path" "root" "root" \
        && path_mode_has_no_bits "$path" "7077"; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

access_file_0640_root_group_ok() {
    path="$1"
    group_a="$2"
    group_b="$3"

    [ -e "$path" ] || return 1
    [ "$(stat -Lc '%U' "$path" 2>/dev/null)" = "root" ] || return 1
    group="$(stat -Lc '%G' "$path" 2>/dev/null)" || return 1
    [ "$group" = "$group_a" ] || [ "$group" = "$group_b" ] || return 1
    path_mode_has_no_bits "$path" "7137"
}

audit_allow_deny_access() {
    control_id="$1"
    title="$2"
    installed_check="$3"
    allow_file="$4"
    deny_file="$5"
    group_a="$6"
    group_b="$7"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if ! "$installed_check"; then
        na_control "$control_id" "$title"
    elif ! access_file_0640_root_group_ok "$allow_file" "$group_a" "$group_b"; then
        fail_control "$control_id" "$title"
    elif [ -e "$deny_file" ] && ! access_file_0640_root_group_ok "$deny_file" "$group_a" "$group_b"; then
        fail_control "$control_id" "$title"
    else
        pass_control "$control_id" "$title"
    fi
}

audit_2_4_1_1() {
    control_id="2.4.1.1"
    title="Ensure cron daemon is enabled and active"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    unit="$(cron_unit_name)"

    if ! cron_installed; then
        na_control "$control_id" "$title"
    elif [ -n "$unit" ] && unit_enabled_and_active "$unit"; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_2_4_1_2() {
    audit_cron_file_access_0600 "2.4.1.2" "Ensure access to /etc/crontab is configured" "/etc/crontab" ""
}

audit_2_4_1_3() {
    audit_cron_file_access_0600 "2.4.1.3" "Ensure access to /etc/cron.hourly is configured" "/etc/cron.hourly" ""
}

audit_2_4_1_4() {
    audit_cron_file_access_0600 "2.4.1.4" "Ensure access to /etc/cron.daily is configured" "/etc/cron.daily" ""
}

audit_2_4_1_5() {
    audit_cron_file_access_0600 "2.4.1.5" "Ensure access to /etc/cron.weekly is configured" "/etc/cron.weekly" ""
}

audit_2_4_1_6() {
    audit_cron_file_access_0600 "2.4.1.6" "Ensure access to /etc/cron.monthly is configured" "/etc/cron.monthly" ""
}

audit_2_4_1_7() {
    audit_cron_file_access_0600 "2.4.1.7" "Ensure access to /etc/cron.yearly is configured" "/etc/cron.yearly" "missing-ok"
}

audit_2_4_1_8() {
    audit_cron_file_access_0600 "2.4.1.8" "Ensure access to /etc/cron.d is configured" "/etc/cron.d" ""
}

audit_2_4_1_9() {
    audit_allow_deny_access \
        "2.4.1.9" \
        "Ensure access to crontab is configured" \
        "cron_installed" \
        "/etc/cron.allow" \
        "/etc/cron.deny" \
        "root" \
        "crontab"
}

at_installed() {
    package_installed "at" || command -v at >/dev/null 2>&1
}

audit_2_4_2_1() {
    audit_allow_deny_access \
        "2.4.2.1" \
        "Ensure access to at is configured" \
        "at_installed" \
        "/etc/at.allow" \
        "/etc/at.deny" \
        "root" \
        "daemon"
}

audit_3_1_1() {
    control_id="3.1.1"
    title="Ensure IPv6 status is identified"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0
    manual_control "$control_id" "$title"
}

wireless_modules_disabled() {
    wireless_dirs="$(find /sys/class/net/*/ -type d -name wireless 2>/dev/null)"

    [ -n "$wireless_dirs" ] || return 0

    while IFS= read -r wireless_dir; do
        driver_dir="$(dirname "$wireless_dir")"
        module_name="$(basename "$(readlink -f "$driver_dir/device/driver/module" 2>/dev/null)")"
        [ -n "$module_name" ] || return 1

        loadable="$(modprobe -n -v "$module_name" 2>/dev/null)"
        grep -Pq -- '^\h*install\s+/bin/(true|false)' <<< "$loadable" || return 1
        lsmod | awk '{print $1}' | grep -Fxq "$module_name" && return 1
        modprobe --showconfig 2>/dev/null | grep -Pq -- "^\h*blacklist\h+${module_name}\b" || return 1
    done <<< "$wireless_dirs"

    return 0
}

audit_3_1_2() {
    control_id="3.1.2"
    title="Ensure wireless interfaces are not available"
    applicability="l1-server"

    should_run_control "$control_id" "$applicability" || return 0

    if wireless_modules_disabled; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_3_1_3() {
    audit_package_services_not_in_use \
        "3.1.3" \
        "Ensure bluetooth services are not in use" \
        "l1-server,l2-workstation" \
        "bluez" \
        "bluetooth.service"
}

audit_3_2_1() {
    audit_kernel_module_not_available \
        "3.2.1" \
        "Ensure atm kernel module is not available" \
        "atm" \
        "net" \
        "l1-server,l1-workstation"
}

audit_3_2_2() {
    audit_kernel_module_not_available \
        "3.2.2" \
        "Ensure can kernel module is not available" \
        "can" \
        "net" \
        "l1-server,l1-workstation"
}

audit_3_2_3() {
    audit_kernel_module_not_available \
        "3.2.3" \
        "Ensure dccp kernel module is not available" \
        "dccp" \
        "net" \
        "l1-server,l1-workstation"
}

audit_3_2_4() {
    audit_kernel_module_not_available \
        "3.2.4" \
        "Ensure rds kernel module is not available" \
        "rds" \
        "net" \
        "l1-server,l1-workstation"
}

audit_3_2_5() {
    audit_kernel_module_not_available \
        "3.2.5" \
        "Ensure sctp kernel module is not available" \
        "sctp" \
        "net" \
        "l1-server,l1-workstation"
}

audit_3_2_6() {
    audit_kernel_module_not_available \
        "3.2.6" \
        "Ensure tipc kernel module is not available" \
        "tipc" \
        "net" \
        "l1-server,l1-workstation"
}

ipv6_disabled() {
    if [ -e /sys/module/ipv6/parameters/disable ] \
        && ! grep -Pqs -- '^\h*0\b' /sys/module/ipv6/parameters/disable; then
        return 0
    fi

    sysctl net.ipv6.conf.all.disable_ipv6 2>/dev/null \
        | grep -Pqs -- '^\h*net\.ipv6\.conf\.all\.disable_ipv6\h*=\h*1\b' \
        && sysctl net.ipv6.conf.default.disable_ipv6 2>/dev/null \
            | grep -Pqs -- '^\h*net\.ipv6\.conf\.default\.disable_ipv6\h*=\h*1\b'
}

audit_ipv6_sysctl_parameter() {
    control_id="$1"
    title="$2"
    parameter="$3"
    expected_regex="$4"
    applicability="$5"

    should_run_control "$control_id" "$applicability" || return 0

    if ipv6_disabled; then
        na_control "$control_id" "$title"
    else
        audit_sysctl_parameter "$control_id" "$title" "$parameter" "$expected_regex" "$applicability"
    fi
}

audit_3_3_1_1() {
    audit_sysctl_parameter "3.3.1.1" "Ensure net.ipv4.ip_forward is configured" "net.ipv4.ip_forward" "0" "l1-workstation,l2-server"
}

audit_3_3_1_2() {
    audit_sysctl_parameter "3.3.1.2" "Ensure net.ipv4.conf.all.forwarding is configured" "net.ipv4.conf.all.forwarding" "0" "l1-server,l1-workstation"
}

audit_3_3_1_3() {
    audit_sysctl_parameter "3.3.1.3" "Ensure net.ipv4.conf.default.forwarding is configured" "net.ipv4.conf.default.forwarding" "0" "l1-server,l1-workstation"
}

audit_3_3_1_4() {
    audit_sysctl_parameter "3.3.1.4" "Ensure net.ipv4.conf.all.send_redirects is configured" "net.ipv4.conf.all.send_redirects" "0" "l1-server,l1-workstation"
}

audit_3_3_1_5() {
    audit_sysctl_parameter "3.3.1.5" "Ensure net.ipv4.conf.default.send_redirects is configured" "net.ipv4.conf.default.send_redirects" "0" "l1-server,l1-workstation"
}

audit_3_3_1_6() {
    audit_sysctl_parameter "3.3.1.6" "Ensure net.ipv4.icmp_ignore_bogus_error_responses is configured" "net.ipv4.icmp_ignore_bogus_error_responses" "1" "l1-server,l1-workstation"
}

audit_3_3_1_7() {
    audit_sysctl_parameter "3.3.1.7" "Ensure net.ipv4.icmp_echo_ignore_broadcasts is configured" "net.ipv4.icmp_echo_ignore_broadcasts" "1" "l1-server,l1-workstation"
}

audit_3_3_1_8() {
    audit_sysctl_parameter "3.3.1.8" "Ensure net.ipv4.conf.all.accept_redirects is configured" "net.ipv4.conf.all.accept_redirects" "0" "l1-server,l1-workstation"
}

audit_3_3_1_9() {
    audit_sysctl_parameter "3.3.1.9" "Ensure net.ipv4.conf.default.accept_redirects is configured" "net.ipv4.conf.default.accept_redirects" "0" "l1-server,l1-workstation"
}

audit_3_3_1_10() {
    audit_sysctl_parameter "3.3.1.10" "Ensure net.ipv4.conf.all.secure_redirects is configured" "net.ipv4.conf.all.secure_redirects" "0" "l1-server,l1-workstation"
}

audit_3_3_1_11() {
    audit_sysctl_parameter "3.3.1.11" "Ensure net.ipv4.conf.default.secure_redirects is configured" "net.ipv4.conf.default.secure_redirects" "0" "l1-server,l1-workstation"
}

audit_3_3_1_12() {
    audit_sysctl_parameter "3.3.1.12" "Ensure net.ipv4.conf.all.rp_filter is configured" "net.ipv4.conf.all.rp_filter" "1" "l1-server,l1-workstation"
}

audit_3_3_1_13() {
    audit_sysctl_parameter "3.3.1.13" "Ensure net.ipv4.conf.default.rp_filter is configured" "net.ipv4.conf.default.rp_filter" "1" "l1-server,l1-workstation"
}

audit_3_3_1_14() {
    audit_sysctl_parameter "3.3.1.14" "Ensure net.ipv4.conf.all.accept_source_route is configured" "net.ipv4.conf.all.accept_source_route" "0" "l1-server,l1-workstation"
}

audit_3_3_1_15() {
    audit_sysctl_parameter "3.3.1.15" "Ensure net.ipv4.conf.default.accept_source_route is configured" "net.ipv4.conf.default.accept_source_route" "0" "l1-server,l1-workstation"
}

audit_3_3_1_16() {
    audit_sysctl_parameter "3.3.1.16" "Ensure net.ipv4.conf.all.log_martians is configured" "net.ipv4.conf.all.log_martians" "1" "l1-server,l1-workstation"
}

audit_3_3_1_17() {
    audit_sysctl_parameter "3.3.1.17" "Ensure net.ipv4.conf.default.log_martians is configured" "net.ipv4.conf.default.log_martians" "1" "l1-server,l1-workstation"
}

audit_3_3_1_18() {
    audit_sysctl_parameter "3.3.1.18" "Ensure net.ipv4.tcp_syncookies is configured" "net.ipv4.tcp_syncookies" "1" "l1-server,l1-workstation"
}

audit_3_3_2_1() {
    audit_ipv6_sysctl_parameter "3.3.2.1" "Ensure net.ipv6.conf.all.forwarding is configured" "net.ipv6.conf.all.forwarding" "0" "l1-server,l1-workstation"
}

audit_3_3_2_2() {
    audit_ipv6_sysctl_parameter "3.3.2.2" "Ensure net.ipv6.conf.default.forwarding is configured" "net.ipv6.conf.default.forwarding" "0" "l1-server,l1-workstation"
}

audit_3_3_2_3() {
    audit_ipv6_sysctl_parameter "3.3.2.3" "Ensure net.ipv6.conf.all.accept_redirects is configured" "net.ipv6.conf.all.accept_redirects" "0" "l1-server,l1-workstation"
}

audit_3_3_2_4() {
    audit_ipv6_sysctl_parameter "3.3.2.4" "Ensure net.ipv6.conf.default.accept_redirects is configured" "net.ipv6.conf.default.accept_redirects" "0" "l1-server,l1-workstation"
}

audit_3_3_2_5() {
    audit_ipv6_sysctl_parameter "3.3.2.5" "Ensure net.ipv6.conf.all.accept_source_route is configured" "net.ipv6.conf.all.accept_source_route" "0" "l1-server,l1-workstation"
}

audit_3_3_2_6() {
    audit_ipv6_sysctl_parameter "3.3.2.6" "Ensure net.ipv6.conf.default.accept_source_route is configured" "net.ipv6.conf.default.accept_source_route" "0" "l1-server,l1-workstation"
}

audit_3_3_2_7() {
    audit_ipv6_sysctl_parameter "3.3.2.7" "Ensure net.ipv6.conf.all.accept_ra is configured" "net.ipv6.conf.all.accept_ra" "0" "l1-server,l1-workstation"
}

audit_3_3_2_8() {
    audit_ipv6_sysctl_parameter "3.3.2.8" "Ensure net.ipv6.conf.default.accept_ra is configured" "net.ipv6.conf.default.accept_ra" "0" "l1-server,l1-workstation"
}

ufw_installed() {
    package_installed "ufw"
}

ufw_active() {
    command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q '^Status: active'
}

ufw_default_policy_field() {
    field="$1"
    default_line="$(ufw status verbose 2>/dev/null | awk -F',' '$1~/Default/ {print; exit}')"

    case "$field" in
        1) printf '%s\n' "$default_line" | cut -d',' -f1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' ;;
        2) printf '%s\n' "$default_line" | cut -d',' -f2 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' ;;
        3) printf '%s\n' "$default_line" | cut -d',' -f3 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' ;;
    esac
}

audit_4_1_1() {
    control_id="4.1.1"
    title="Ensure ufw is installed"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if ufw_installed; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_4_1_2() {
    control_id="4.1.2"
    title="Ensure ufw service is configured"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if ! ufw_installed; then
        na_control "$control_id" "$title"
    elif unit_enabled_and_active "ufw.service" && ufw_active; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_4_1_3() {
    control_id="4.1.3"
    title="Ensure ufw incoming default is configured"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if ! ufw_installed; then
        na_control "$control_id" "$title"
        return 0
    fi

    policy="$(ufw_default_policy_field 1)"
    if grep -Eq 'Default: (deny|reject) \(incoming\)' <<< "$policy"; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_4_1_4() {
    control_id="4.1.4"
    title="Ensure ufw outgoing default is configured"
    applicability="l2-server,l2-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if ! ufw_installed; then
        na_control "$control_id" "$title"
        return 0
    fi

    policy="$(ufw_default_policy_field 2)"
    if grep -Eq '^(deny|reject) \(outgoing\)' <<< "$policy"; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_4_1_5() {
    control_id="4.1.5"
    title="Ensure ufw routed default is configured"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if ! ufw_installed; then
        na_control "$control_id" "$title"
        return 0
    fi

    policy="$(ufw_default_policy_field 3)"
    if grep -Eq '^(disabled|deny) \(routed\)' <<< "$policy"; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

sshd_command() {
    readlink -e /usr/sbin/sshd 2>/dev/null || readlink -e /sbin/sshd 2>/dev/null
}

ssh_keygen_command() {
    readlink -e /usr/bin/ssh-keygen 2>/dev/null || readlink -e /bin/ssh-keygen 2>/dev/null
}

sshd_available() {
    [ -n "$(sshd_command)" ]
}

sshd_test_args() {
    local config_file

    config_file="$(readlink -e /etc/ssh/sshd_config 2>/dev/null)"
    printf '%s\n' "-T"
    if [ -n "$config_file" ] \
        && grep -qiE '^\s*Match\s+(User|Group|Host|LocalAddress|LocalPort|Address)' "$config_file" 2>/dev/null; then
        printf '%s\n' "-C" "user=root,host=localhost,addr=127.0.0.1"
    fi
}

sshd_effective_config() {
    local sshd_cmd
    local args=()

    sshd_cmd="$(sshd_command)"
    [ -n "$sshd_cmd" ] || return 1
    mapfile -t args < <(sshd_test_args)
    "$sshd_cmd" "${args[@]}" 2>/dev/null
}

sshd_effective_value() {
    key="$1"

    sshd_effective_config | awk -v key="$key" '$1 == key {print $2; exit}'
}

audit_sshd_expected_value() {
    control_id="$1"
    title="$2"
    key="$3"
    expected="$4"
    applicability="$5"

    should_run_control "$control_id" "$applicability" || return 0

    if ! sshd_available; then
        na_control "$control_id" "$title"
    elif [ "$(sshd_effective_value "$key")" = "$expected" ]; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

sshd_algorithm_list_has_weak_value() {
    algorithm_key="$1"
    weak_values="$2"
    local configured
    local algorithm
    local weak

    configured="$(sshd_effective_value "$algorithm_key")"
    [ -n "$configured" ] || return 0

    IFS=',' read -r -a algorithms <<< "$configured"
    for algorithm in "${algorithms[@]}"; do
        for weak in $weak_values; do
            [ "$algorithm" = "$weak" ] && return 0
        done
    done

    return 1
}

audit_sshd_no_weak_algorithms() {
    control_id="$1"
    title="$2"
    algorithm_key="$3"
    weak_values="$4"
    applicability="$5"

    should_run_control "$control_id" "$applicability" || return 0

    if ! sshd_available; then
        na_control "$control_id" "$title"
    elif sshd_algorithm_list_has_weak_value "$algorithm_key" "$weak_values"; then
        fail_control "$control_id" "$title"
    else
        pass_control "$control_id" "$title"
    fi
}

sshd_config_file_access_ok() {
    [ -e /etc/ssh/sshd_config ] \
        && path_has_owner_group /etc/ssh/sshd_config "root" "root" \
        && path_mode_has_no_bits /etc/ssh/sshd_config "177" \
        && [ -z "$(find_files_with_bad_access /etc/ssh/sshd_config.d '*.conf' 077)" ]
}

sshd_host_key_files_ok() {
    suffix="$1"
    disallowed_mask="$2"
    local sshd_cmd
    local keygen_cmd
    local hostkey
    local key_file
    local saw_key=0

    sshd_cmd="$(sshd_command)"
    keygen_cmd="$(ssh_keygen_command)"
    [ -n "$sshd_cmd" ] && [ -n "$keygen_cmd" ] || return 1

    while IFS= read -r hostkey; do
        key_file="${hostkey}${suffix}"
        if "$keygen_cmd" -lf "$key_file" >/dev/null 2>&1; then
            saw_key=1
            path_has_owner_group "$key_file" "root" "root" || return 1
            path_mode_has_no_bits "$key_file" "$disallowed_mask" || return 1
        fi
    done < <(sshd_effective_config | awk '$1 == "hostkey" {print $2}')

    [ "$saw_key" -eq 1 ]
}

sshd_has_access_control() {
    sshd_effective_config | grep -Piq -- '^\h*(allow|deny)(users|groups)\h+\H+'
}

sshd_banner_ok() {
    local banner_path
    local os_id

    banner_path="$(sshd_effective_value "banner")"
    [ -n "$banner_path" ] && [ "$banner_path" != "none" ] || return 1
    [ "${banner_path#/}" != "$banner_path" ] || return 1
    [ -s "$banner_path" ] || return 1

    os_id="$(grep '^ID=' /etc/os-release 2>/dev/null | cut -d= -f2 | sed -e 's/"//g')"
    if [ -n "$os_id" ]; then
        ! grep -Psiq -- "(\\\\v|\\\\r|\\\\m|\\\\s|\\b${os_id}\\b)" "$banner_path" 2>/dev/null
    else
        ! grep -Psiq -- "(\\\\v|\\\\r|\\\\m|\\\\s)" "$banner_path" 2>/dev/null
    fi
}

sshd_client_alive_ok() {
    local interval
    local count_max

    interval="$(sshd_effective_value "clientaliveinterval")"
    count_max="$(sshd_effective_value "clientalivecountmax")"

    [[ "$interval" =~ ^[0-9]+$ ]] && [[ "$count_max" =~ ^[0-9]+$ ]] || return 1
    [ "$interval" -gt 0 ] && [ "$interval" -le 15 ] && [ "$count_max" -gt 0 ] && [ "$count_max" -le 3 ]
}

sshd_logingracetime_seconds() {
    value="$1"

    case "$value" in
        *s) printf '%s\n' "${value%s}" ;;
        *m) printf '%s\n' "$(( ${value%m} * 60 ))" ;;
        *h) printf '%s\n' "$(( ${value%h} * 3600 ))" ;;
        *) printf '%s\n' "$value" ;;
    esac
}

sshd_logingracetime_ok() {
    local value
    local seconds

    value="$(sshd_effective_value "logingracetime")"
    seconds="$(sshd_logingracetime_seconds "$value")"

    [[ "$seconds" =~ ^[0-9]+$ ]] || return 1
    [ "$seconds" -ge 1 ] && [ "$seconds" -le 60 ]
}

sshd_loglevel_ok() {
    case "$(sshd_effective_value "loglevel")" in
        INFO|VERBOSE) return 0 ;;
        *) return 1 ;;
    esac
}

sshd_max_value_ok() {
    key="$1"
    max_value="$2"
    local value

    value="$(sshd_effective_value "$key")"
    [[ "$value" =~ ^[0-9]+$ ]] || return 1
    [ "$value" -le "$max_value" ]
}

sshd_maxstartups_ok() {
    local value
    local start
    local rate
    local full

    value="$(sshd_effective_value "maxstartups")"
    IFS=':' read -r start rate full <<< "$value"

    [[ "$start" =~ ^[0-9]+$ ]] && [[ "$rate" =~ ^[0-9]+$ ]] && [[ "$full" =~ ^[0-9]+$ ]] || return 1
    [ "$start" -le 10 ] && [ "$rate" -le 30 ] && [ "$full" -le 60 ]
}

sshd_version_ge_9_9() {
    local sshd_cmd
    local version
    local major
    local minor

    sshd_cmd="$(sshd_command)"
    version="$("$sshd_cmd" -V 2>&1 | grep -Psio 'openssh_[0-9]+\.[0-9]+' | awk -F'_' '{print $2}' | head -n 1)"
    major="${version%%.*}"
    minor="${version#*.}"

    [[ "$major" =~ ^[0-9]+$ ]] && [[ "$minor" =~ ^[0-9]+$ ]] || return 1
    [ "$major" -gt 9 ] || { [ "$major" -eq 9 ] && [ "$minor" -ge 9 ]; }
}

sshd_post_quantum_kex_ok() {
    local kex

    kex="$(sshd_effective_value "kexalgorithms")"
    grep -q 'sntrup761x25519-sha512' <<< "$kex" || return 1
    if sshd_version_ge_9_9; then
        grep -q 'mlkem768x25519-sha256' <<< "$kex" || return 1
    fi
}

listen_address_is_private() {
    value="$1"
    local address
    local first
    local second

    address="$value"
    address="${address#[}"
    address="${address%%]*}"
    address="${address%:*}"

    case "$address" in
        10.*|192.168.*|fc*:*|fd*:*|fe80:*) return 0 ;;
        0.0.0.0|::|\*) return 1 ;;
    esac

    first="${address%%.*}"
    second="${address#*.}"
    second="${second%%.*}"
    if [[ "$first" =~ ^[0-9]+$ ]] && [[ "$second" =~ ^[0-9]+$ ]] \
        && [ "$first" -eq 172 ] && [ "$second" -ge 16 ] && [ "$second" -le 31 ]; then
        return 0
    fi

    return 1
}

sshd_listenaddress_status() {
    local address
    local saw_address=0
    local saw_hostname=0

    while IFS= read -r address; do
        address="${address#listenaddress }"
        [ -n "$address" ] || continue
        saw_address=1

        if grep -Eq '(^|\[)(0\.0\.0\.0|::|\*)(\]|:|$)' <<< "$address"; then
            return 1
        elif listen_address_is_private "$address"; then
            return 0
        elif ! grep -Eq '^[[]?[0-9a-fA-F:.]+[]]?(:[0-9]+)?$' <<< "$address"; then
            saw_hostname=1
        fi
    done < <(sshd_effective_config | awk '$1 == "listenaddress" {print $0}')

    [ "$saw_address" -eq 0 ] && return 1
    [ "$saw_hostname" -eq 1 ] && return 2
    return 1
}

audit_5_1_1() {
    control_id="5.1.1"
    title="Ensure access to /etc/ssh/sshd_config is configured"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if ! sshd_available; then
        na_control "$control_id" "$title"
    elif sshd_config_file_access_ok; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_5_1_2() {
    control_id="5.1.2"
    title="Ensure access to SSH private host key files is configured"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if ! sshd_available; then
        na_control "$control_id" "$title"
    elif sshd_host_key_files_ok "" "077"; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_5_1_3() {
    control_id="5.1.3"
    title="Ensure access to SSH public host key files is configured"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if ! sshd_available; then
        na_control "$control_id" "$title"
    elif sshd_host_key_files_ok ".pub" "133"; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_5_1_4() {
    control_id="5.1.4"
    title="Ensure sshd access is configured"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if ! sshd_available; then
        na_control "$control_id" "$title"
    elif sshd_has_access_control; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_5_1_5() {
    control_id="5.1.5"
    title="Ensure sshd Banner is configured"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if ! sshd_available; then
        na_control "$control_id" "$title"
    elif sshd_banner_ok; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_5_1_6() {
    audit_sshd_no_weak_algorithms \
        "5.1.6" \
        "Ensure sshd Ciphers are configured" \
        "ciphers" \
        "3des-cbc blowfish-cbc cast128-cbc aes128-cbc aes192-cbc aes256-cbc arcfour arcfour128 arcfour256 rijndael-cbc@lysator.liu.se" \
        "l1-server,l1-workstation"
}

audit_5_1_7() {
    control_id="5.1.7"
    title="Ensure sshd ClientAliveInterval and ClientAliveCountMax are configured"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if ! sshd_available; then
        na_control "$control_id" "$title"
    elif sshd_client_alive_ok; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_5_1_8() {
    audit_sshd_expected_value "5.1.8" "Ensure sshd DisableForwarding is enabled" "disableforwarding" "yes" "l2-server,l1-workstation"
}

audit_5_1_9() {
    audit_sshd_expected_value "5.1.9" "Ensure sshd GSSAPIAuthentication is disabled" "gssapiauthentication" "no" "l2-server,l1-workstation"
}

audit_5_1_10() {
    audit_sshd_expected_value "5.1.10" "Ensure sshd HostbasedAuthentication is disabled" "hostbasedauthentication" "no" "l1-server,l1-workstation"
}

audit_5_1_11() {
    audit_sshd_expected_value "5.1.11" "Ensure sshd IgnoreRhosts is enabled" "ignorerhosts" "yes" "l1-server,l1-workstation"
}

audit_5_1_12() {
    audit_sshd_no_weak_algorithms \
        "5.1.12" \
        "Ensure sshd KexAlgorithms is configured" \
        "kexalgorithms" \
        "diffie-hellman-group1-sha1 diffie-hellman-group14-sha1 diffie-hellman-group-exchange-sha1" \
        "l1-server,l1-workstation"
}

audit_5_1_13() {
    control_id="5.1.13"
    title="Ensure sshd LoginGraceTime is configured"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if ! sshd_available; then
        na_control "$control_id" "$title"
    elif sshd_logingracetime_ok; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_5_1_14() {
    control_id="5.1.14"
    title="Ensure sshd LogLevel is configured"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if ! sshd_available; then
        na_control "$control_id" "$title"
    elif sshd_loglevel_ok; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_5_1_15() {
    audit_sshd_no_weak_algorithms \
        "5.1.15" \
        "Ensure sshd MACs are configured" \
        "macs" \
        "hmac-md5 hmac-md5-96 hmac-ripemd160 hmac-sha1-96 umac-64@openssh.com hmac-md5-etm@openssh.com hmac-md5-96-etm@openssh.com hmac-ripemd160-etm@openssh.com hmac-sha1-96-etm@openssh.com umac-64-etm@openssh.com umac-128-etm@openssh.com" \
        "l1-server,l1-workstation"
}

audit_5_1_16() {
    control_id="5.1.16"
    title="Ensure sshd MaxAuthTries is configured"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if ! sshd_available; then
        na_control "$control_id" "$title"
    elif sshd_max_value_ok "maxauthtries" 4; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_5_1_17() {
    control_id="5.1.17"
    title="Ensure sshd MaxStartups is configured"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if ! sshd_available; then
        na_control "$control_id" "$title"
    elif sshd_maxstartups_ok; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_5_1_18() {
    control_id="5.1.18"
    title="Ensure sshd MaxSessions is configured"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if ! sshd_available; then
        na_control "$control_id" "$title"
    elif sshd_max_value_ok "maxsessions" 10; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_5_1_19() {
    audit_sshd_expected_value "5.1.19" "Ensure sshd PermitEmptyPasswords is disabled" "permitemptypasswords" "no" "l1-server,l1-workstation"
}

audit_5_1_20() {
    audit_sshd_expected_value "5.1.20" "Ensure sshd PermitRootLogin is disabled" "permitrootlogin" "no" "l1-server,l1-workstation"
}

audit_5_1_21() {
    audit_sshd_expected_value "5.1.21" "Ensure sshd PermitUserEnvironment is disabled" "permituserenvironment" "no" "l1-server,l1-workstation"
}

audit_5_1_22() {
    audit_sshd_expected_value "5.1.22" "Ensure sshd UsePAM is enabled" "usepam" "yes" "l1-server,l1-workstation"
}

audit_5_1_23() {
    control_id="5.1.23"
    title="Ensure sshd post-quantum cryptography key exchange algorithms are configured"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if ! sshd_available; then
        na_control "$control_id" "$title"
    elif sshd_post_quantum_kex_ok; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_5_1_24() {
    control_id="5.1.24"
    title="Ensure sshd ListenAddress is configured"
    applicability="l2-server,l2-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if ! sshd_available; then
        na_control "$control_id" "$title"
        return 0
    fi

    sshd_listenaddress_status
    case "$?" in
        0) pass_control "$control_id" "$title" ;;
        2) manual_control "$control_id" "$title" ;;
        *) fail_control "$control_id" "$title" ;;
    esac
}

sudo_installed() {
    package_installed "sudo" || package_installed "sudo-ldap"
}

sudoers_files() {
    printf '%s\n' "/etc/sudoers"
    if [ -d /etc/sudoers.d ]; then
        find /etc/sudoers.d -type f ! -name '*~' ! -name '*.*' -print 2>/dev/null
    fi
}

grep_sudoers() {
    pattern="$1"

    sudoers_files | xargs -r grep -Psi -- "$pattern" 2>/dev/null
}

sudoers_has_use_pty() {
    grep_sudoers '^\h*Defaults\h+([^#\n\r]+,\h*)?use_pty\b' | grep -q .
}

sudoers_has_disabled_use_pty() {
    grep_sudoers '^\h*Defaults\h+([^#\n\r]+,\h*)?!use_pty\b' | grep -q .
}

sudoers_has_logfile() {
    grep_sudoers '^\h*Defaults\h+([^#]+,\h*)?logfile\h*=\h*("|'"'"')?\H+("|'"'"')?(,\h*\H+\h*)*\h*(#.*)?$' | grep -q .
}

sudoers_has_nopasswd() {
    grep_sudoers '^[^#].*NOPASSWD' | grep -q .
}

sudoers_has_no_authenticate() {
    grep_sudoers '^[^#].*!\h*authenticate' | grep -q .
}

sudo_timeout_value_ok() {
    timeout_value="$1"

    awk -v value="$timeout_value" 'BEGIN { exit !(value >= 0 && value <= 15) }'
}

sudo_timestamp_timeout_ok() {
    local found_value=0
    local timeout_value
    local default_timeout

    while IFS= read -r timeout_value; do
        found_value=1
        sudo_timeout_value_ok "$timeout_value" || return 1
    done < <(grep_sudoers '^[^#].*timestamp_timeout\h*=\h*-?[0-9]+([.][0-9]+)?' \
        | grep -Po 'timestamp_timeout\h*=\h*\K-?[0-9]+([.][0-9]+)?')

    [ "$found_value" -eq 1 ] && return 0

    default_timeout="$(sudo -V 2>/dev/null \
        | awk -F: '/Authentication timestamp timeout/ {gsub(/^[[:space:]]+| minutes.*$/, "", $2); print $2; exit}')"
    [ -n "$default_timeout" ] || return 1
    sudo_timeout_value_ok "$default_timeout"
}

su_restricted_to_empty_group() {
    local line
    local group_name
    local group_entry

    line="$(grep -Pi '^\h*auth\h+(required|requisite)\h+pam_wheel\.so\h+.*\buse_uid\b.*\bgroup=\H+\b|^\h*auth\h+(required|requisite)\h+pam_wheel\.so\h+.*\bgroup=\H+\b.*\buse_uid\b' /etc/pam.d/su 2>/dev/null | head -n 1)"
    [ -n "$line" ] || return 1

    group_name="$(printf '%s\n' "$line" | grep -Po 'group=\K[^[:space:]#]+' | head -n 1)"
    [ -n "$group_name" ] || return 1

    group_entry="$(getent group "$group_name" 2>/dev/null)"
    [ -n "$group_entry" ] || return 1
    [ -z "${group_entry##*:}" ]
}

audit_5_2_1() {
    control_id="5.2.1"
    title="Ensure sudo is installed"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if sudo_installed; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_5_2_2() {
    control_id="5.2.2"
    title="Ensure sudo commands use pty"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if ! sudo_installed; then
        na_control "$control_id" "$title"
    elif sudoers_has_use_pty && ! sudoers_has_disabled_use_pty; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_5_2_3() {
    control_id="5.2.3"
    title="Ensure sudo log file exists"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if ! sudo_installed; then
        na_control "$control_id" "$title"
    elif sudoers_has_logfile; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_5_2_4() {
    control_id="5.2.4"
    title="Ensure users must provide password for escalation"
    applicability="l2-server,l2-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if ! sudo_installed; then
        na_control "$control_id" "$title"
    elif sudoers_has_nopasswd; then
        fail_control "$control_id" "$title"
    else
        pass_control "$control_id" "$title"
    fi
}

audit_5_2_5() {
    control_id="5.2.5"
    title="Ensure re-authentication for privilege escalation is not disabled globally"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if ! sudo_installed; then
        na_control "$control_id" "$title"
    elif sudoers_has_no_authenticate; then
        fail_control "$control_id" "$title"
    else
        pass_control "$control_id" "$title"
    fi
}

audit_5_2_6() {
    control_id="5.2.6"
    title="Ensure sudo timestamp_timeout is configured"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if ! sudo_installed; then
        na_control "$control_id" "$title"
    elif sudo_timestamp_timeout_ok; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_5_2_7() {
    control_id="5.2.7"
    title="Ensure access to the su command is restricted"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if su_restricted_to_empty_group; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

package_not_upgradable() {
    package_name="$1"

    apt list --upgradable 2>/dev/null | grep -Pv '^Listing\.\.\.' | grep -Pq "^${package_name}\b"
    [ "$?" -ne 0 ]
}

audit_package_installed_and_current() {
    control_id="$1"
    title="$2"
    package_name="$3"
    applicability="$4"

    should_run_control "$control_id" "$applicability" || return 0

    if package_installed "$package_name" && package_not_upgradable "$package_name"; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

pam_module_in_file() {
    module_name="$1"
    pam_file="$2"

    [ -f "$pam_file" ] && grep -Pq -- "\\b${module_name}\\.so\\b" "$pam_file" 2>/dev/null
}

audit_pam_module_in_files() {
    control_id="$1"
    title="$2"
    module_name="$3"
    applicability="$4"
    shift 4

    should_run_control "$control_id" "$applicability" || return 0

    for pam_file in "$@"; do
        if ! pam_module_in_file "$module_name" "$pam_file"; then
            fail_control "$control_id" "$title"
            return 0
        fi
    done

    pass_control "$control_id" "$title"
}

audit_5_3_1_1() {
    audit_package_installed_and_current \
        "5.3.1.1" \
        "Ensure latest version of pam is installed" \
        "libpam-runtime" \
        "l1-server,l1-workstation"
}

audit_5_3_1_2() {
    audit_package_installed_and_current \
        "5.3.1.2" \
        "Ensure latest version of libpam-modules is installed" \
        "libpam-modules" \
        "l1-server,l1-workstation"
}

audit_5_3_1_3() {
    audit_package_installed_and_current \
        "5.3.1.3" \
        "Ensure latest version of libpam-pwquality is installed" \
        "libpam-pwquality" \
        "l1-server,l1-workstation"
}

audit_5_3_1_4() {
    audit_package_installed_and_current \
        "5.3.1.4" \
        "Ensure latest version of cracklib-runtime is installed" \
        "cracklib-runtime" \
        "l1-server,l1-workstation"
}

audit_5_3_2_1() {
    audit_pam_module_in_files \
        "5.3.2.1" \
        "Ensure pam_unix module is enabled" \
        "pam_unix" \
        "l1-server,l1-workstation" \
        "/etc/pam.d/common-account" \
        "/etc/pam.d/common-auth" \
        "/etc/pam.d/common-password" \
        "/etc/pam.d/common-session" \
        "/etc/pam.d/common-session-noninteractive"
}

audit_5_3_2_2() {
    audit_pam_module_in_files \
        "5.3.2.2" \
        "Ensure pam_faillock module is enabled" \
        "pam_faillock" \
        "l1-server,l1-workstation" \
        "/etc/pam.d/common-auth" \
        "/etc/pam.d/common-account"
}

audit_5_3_2_3() {
    audit_pam_module_in_files \
        "5.3.2.3" \
        "Ensure pam_pwquality module is enabled" \
        "pam_pwquality" \
        "l1-server,l1-workstation" \
        "/etc/pam.d/common-password"
}

audit_5_3_2_4() {
    audit_pam_module_in_files \
        "5.3.2.4" \
        "Ensure pam_pwhistory module is enabled" \
        "pam_pwhistory" \
        "l1-server,l1-workstation" \
        "/etc/pam.d/common-password"
}

pam_common_files() {
    printf '%s\n' \
        "/etc/pam.d/common-password" \
        "/etc/pam.d/common-auth" \
        "/etc/pam.d/common-account" \
        "/etc/pam.d/common-session" \
        "/etc/pam.d/common-session-noninteractive"
}

grep_existing_files() {
    pattern="$1"
    shift

    grep -PHsi -- "$pattern" "$@" 2>/dev/null
}

pwquality_config_has() {
    pattern="$1"

    grep_existing_files "$pattern" /etc/security/pwquality.conf /etc/security/pwquality.conf.d/*.conf | grep -q .
}

pwquality_config_lacks() {
    pattern="$1"

    ! pwquality_config_has "$pattern"
}

pam_file_has() {
    pattern="$1"
    shift

    grep_existing_files "$pattern" "$@" | grep -q .
}

pam_file_lacks() {
    pattern="$1"
    shift

    ! pam_file_has "$pattern" "$@"
}

faillock_deny_ok() {
    grep -Piq -- '^\h*deny\h*=\h*[1-5]\b' /etc/security/faillock.conf 2>/dev/null \
        && pam_file_lacks '^\h*auth\h+(requisite|required|sufficient)\h+pam_faillock\.so\h+([^#\n\r]+\h+)?deny\h*=\h*(0|[6-9]|[1-9][0-9]+)\b' /etc/pam.d/common-auth
}

faillock_unlock_time_ok() {
    grep -Piq -- '^\h*unlock_time\h*=\h*(0|9[0-9][0-9]|[1-9][0-9]{3,})\b' /etc/security/faillock.conf 2>/dev/null \
        && pam_file_lacks '^\h*auth\h+(requisite|required|sufficient)\h+pam_faillock\.so\h+([^#\n\r]+\h+)?unlock_time\h*=\h*([1-9]|[1-9][0-9]|[1-8][0-9][0-9])\b' /etc/pam.d/common-auth
}

faillock_root_lockout_ok() {
    grep -Piq -- '^\h*(even_deny_root|root_unlock_time\h*=\h*[0-9]+)\b' /etc/security/faillock.conf 2>/dev/null \
        && ! grep -Piq -- '^\h*root_unlock_time\h*=\h*([1-9]|[1-5][0-9])\b' /etc/security/faillock.conf 2>/dev/null \
        && pam_file_lacks '^\h*auth\h+([^#\n\r]+\h+)pam_faillock\.so\h+([^#\n\r]+\h+)?root_unlock_time\h*=\h*([1-9]|[1-5][0-9])\b' /etc/pam.d/common-auth
}

pwquality_option_ok() {
    required_pattern="$1"
    bad_pam_pattern="$2"

    pwquality_config_has "$required_pattern" \
        && pam_file_lacks "$bad_pam_pattern" /etc/pam.d/common-password
}

pwhistory_conf_exists() {
    [ -f /etc/security/pwhistory.conf ]
}

pwhistory_common_password_has() {
    pattern="$1"

    pam_file_has "^\h*password\h+[^#\n\r]+\h+pam_pwhistory\.so\h+([^#\n\r]+\h+)?${pattern}\b" /etc/pam.d/common-password
}

pwhistory_conf_has() {
    pattern="$1"

    grep -Piq -- "^\h*${pattern}\b" /etc/security/pwhistory.conf 2>/dev/null
}

pwhistory_setting_ok() {
    common_pattern="$1"
    conf_pattern="$2"

    pwhistory_common_password_has "$common_pattern" || { pwhistory_conf_exists && pwhistory_conf_has "$conf_pattern"; }
}

pam_unix_common_lacks() {
    arg_pattern="$1"
    local files=()

    mapfile -t files < <(pam_common_files)
    pam_file_lacks "^\h*[^#\n\r]+\h+pam_unix\.so\h+([^#\n\r]+\h+)?${arg_pattern}\b" "${files[@]}"
}

pam_unix_password_has() {
    arg_pattern="$1"

    pam_file_has "^\h*password\h+([^#\n\r]+)\h+pam_unix\.so\h+([^#\n\r]+\h+)?${arg_pattern}\b" /etc/pam.d/common-password
}

audit_5_3_3_1_1() {
    control_id="5.3.3.1.1"
    title="Ensure password failed attempts lockout is configured"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if faillock_deny_ok; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_5_3_3_1_2() {
    control_id="5.3.3.1.2"
    title="Ensure password unlock time is configured"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if faillock_unlock_time_ok; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_5_3_3_1_3() {
    control_id="5.3.3.1.3"
    title="Ensure password failed attempts lockout includes root account"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if faillock_root_lockout_ok; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_5_3_3_2_1() {
    control_id="5.3.3.2.1"
    title="Ensure password number of changed characters is configured"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if pwquality_option_ok '^\h*difok\h*=\h*([2-9]|[1-9][0-9]+)\b' '^\h*password\h+(requisite|required|sufficient)\h+pam_pwquality\.so\h+([^#\n\r]+\h+)?difok\h*=\h*[0-1]\b'; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_5_3_3_2_2() {
    control_id="5.3.3.2.2"
    title="Ensure password length is configured"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if pwquality_option_ok '^\h*minlen\h*=\h*(1[4-9]|[2-9][0-9]|[1-9][0-9]{2,})\b' '^\h*password\h+(requisite|required|sufficient)\h+pam_pwquality\.so\h+([^#\n\r]+\h+)?minlen\h*=\h*([0-9]|1[0-3])\b'; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_5_3_3_2_3() {
    control_id="5.3.3.2.3"
    title="Ensure password complexity is configured"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0
    manual_control "$control_id" "$title"
}

audit_5_3_3_2_4() {
    control_id="5.3.3.2.4"
    title="Ensure password same consecutive characters is configured"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if pwquality_option_ok '^\h*maxrepeat\h*=\h*[1-3]\b' '^\h*password\h+(requisite|required|sufficient)\h+pam_pwquality\.so\h+([^#\n\r]+\h+)?maxrepeat\h*=\h*(0|[4-9]|[1-9][0-9]+)\b'; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_5_3_3_2_5() {
    control_id="5.3.3.2.5"
    title="Ensure password maximum sequential characters is configured"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if pwquality_option_ok '^\h*maxsequence\h*=\h*[1-3]\b' '^\h*password\h+(requisite|required|sufficient)\h+pam_pwquality\.so\h+([^#\n\r]+\h+)?maxsequence\h*=\h*(0|[4-9]|[1-9][0-9]+)\b'; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_5_3_3_2_6() {
    control_id="5.3.3.2.6"
    title="Ensure password dictionary check is enabled"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if pwquality_config_lacks '^\h*dictcheck\h*=\h*0\b' \
        && pam_file_lacks '^\h*password\h+(requisite|required|sufficient)\h+pam_pwquality\.so\h+([^#\n\r]+\h+)?dictcheck\h*=\h*0\b' /etc/pam.d/common-password; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_5_3_3_2_7() {
    control_id="5.3.3.2.7"
    title="Ensure password quality checking is enforced"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if pwquality_config_lacks '^\h*enforcing\h*=\h*0\b' \
        && pam_file_lacks '^\h*password\h+[^#\n\r]+\h+pam_pwquality\.so\h+([^#\n\r]+\h+)?enforcing=0\b' /etc/pam.d/common-password; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_5_3_3_2_8() {
    control_id="5.3.3.2.8"
    title="Ensure password quality is enforced for the root user"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if pwquality_config_has '^\h*enforce_for_root\b'; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_5_3_3_3_1() {
    control_id="5.3.3.3.1"
    title="Ensure password history remember is configured"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if pwhistory_setting_ok 'remember\h*=\h*(2[4-9]|[3-9][0-9]|[1-9][0-9]{2,})' 'remember\h*=\h*(2[4-9]|[3-9][0-9]|[1-9][0-9]{2,})'; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_5_3_3_3_2() {
    control_id="5.3.3.3.2"
    title="Ensure password history is enforced for the root user"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if pwhistory_setting_ok 'enforce_for_root' 'enforce_for_root'; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_5_3_3_3_3() {
    control_id="5.3.3.3.3"
    title="Ensure pam_pwhistory includes use_authtok"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if pwhistory_setting_ok 'use_authtok' 'use_authtok'; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_5_3_3_4_1() {
    control_id="5.3.3.4.1"
    title="Ensure pam_unix does not include nullok"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if pam_unix_common_lacks "nullok"; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_5_3_3_4_2() {
    control_id="5.3.3.4.2"
    title="Ensure pam_unix does not include remember"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if pam_unix_common_lacks 'remember\h*=\h*[0-9]+'; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_5_3_3_4_3() {
    control_id="5.3.3.4.3"
    title="Ensure pam_unix includes a strong password hashing algorithm"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if pam_unix_password_has '(sha512|yescrypt)'; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_5_3_3_4_4() {
    control_id="5.3.3.4.4"
    title="Ensure pam_unix includes use_authtok"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if pam_unix_password_has "use_authtok"; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

login_defs_value() {
    key="$1"

    awk -v key="$key" '$1 == key {value = $2} END {if (value != "") print value}' /etc/login.defs 2>/dev/null
}

login_defs_numeric_between() {
    key="$1"
    min_value="$2"
    max_value="$3"
    local value

    value="$(login_defs_value "$key")"
    [[ "$value" =~ ^[0-9]+$ ]] || return 1
    [ "$value" -ge "$min_value" ] && [ "$value" -le "$max_value" ]
}

login_defs_numeric_min() {
    key="$1"
    min_value="$2"
    local value

    value="$(login_defs_value "$key")"
    [[ "$value" =~ ^[0-9]+$ ]] || return 1
    [ "$value" -ge "$min_value" ]
}

shadow_password_field_between() {
    field_number="$1"
    min_value="$2"
    max_value="$3"

    awk -F: -v field="$field_number" -v min="$min_value" -v max="$max_value" \
        '($2~/^\$.+\$/) {if($field !~ /^[0-9]+$/ || $field < min || $field > max) bad=1} END {exit bad}' \
        /etc/shadow 2>/dev/null
}

shadow_password_field_min() {
    field_number="$1"
    min_value="$2"

    awk -F: -v field="$field_number" -v min="$min_value" \
        '($2~/^\$.+\$/) {if($field !~ /^[0-9]+$/ || $field < min) bad=1} END {exit bad}' \
        /etc/shadow 2>/dev/null
}

login_defs_encrypt_method_strong() {
    grep -Piq -- '^\h*ENCRYPT_METHOD\h+(SHA512|YESCRYPT)\b' /etc/login.defs 2>/dev/null
}

useradd_inactive_default_ok() {
    local value

    value="$(useradd -D 2>/dev/null | awk -F= '$1 == "INACTIVE" {print $2; exit}')"
    [[ "$value" =~ ^-?[0-9]+$ ]] || return 1
    [ "$value" -ge 0 ] && [ "$value" -le 45 ]
}

shadow_inactive_days_ok() {
    awk -F: '($2~/^\$.+\$/) {if($7 != "" && ($7 > 45 || $7 < 0)) bad=1} END {exit bad}' /etc/shadow 2>/dev/null
}

shadow_last_password_change_in_past() {
    local today_days

    today_days="$(( $(date -u +%s) / 86400 ))"
    awk -F: -v today="$today_days" \
        '($2~/^\$.+\$/) {if($3 ~ /^[0-9]+$/ && $3 > today) bad=1} END {exit bad}' \
        /etc/shadow 2>/dev/null
}

audit_5_4_1_1() {
    control_id="5.4.1.1"
    title="Ensure password expiration is configured"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if login_defs_numeric_between "PASS_MAX_DAYS" 1 365 \
        && shadow_password_field_between 5 1 365; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_5_4_1_2() {
    control_id="5.4.1.2"
    title="Ensure minimum password days is configured"
    applicability="l2-server,l2-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if login_defs_numeric_min "PASS_MIN_DAYS" 1 \
        && shadow_password_field_min 4 1; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_5_4_1_3() {
    control_id="5.4.1.3"
    title="Ensure password expiration warning days is configured"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if login_defs_numeric_min "PASS_WARN_AGE" 7 \
        && shadow_password_field_min 6 7; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_5_4_1_4() {
    control_id="5.4.1.4"
    title="Ensure strong password hashing algorithm is configured"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if login_defs_encrypt_method_strong; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_5_4_1_5() {
    control_id="5.4.1.5"
    title="Ensure inactive password lock is configured"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if useradd_inactive_default_ok && shadow_inactive_days_ok; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_5_4_1_6() {
    control_id="5.4.1.6"
    title="Ensure all users last password change date is in the past"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if shadow_last_password_change_in_past; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

uid_zero_only_root() {
    [ "$(awk -F: '($3 == 0) {print $1}' /etc/passwd 2>/dev/null)" = "root" ]
}

primary_gid_zero_ok() {
    awk -F: 'BEGIN {bad=0} $1 == "root" {if ($4 != 0) bad=1} ($1 !~ /^(root|sync|shutdown|halt|operator)$/ && $4 == 0) {bad=1} END {exit bad}' /etc/passwd 2>/dev/null
}

gid_zero_only_root_group() {
    [ "$(awk -F: '($3 == 0) {print $1 ":" $3}' /etc/group 2>/dev/null)" = "root:0" ]
}

root_access_controlled() {
    passwd -S root 2>/dev/null | awk '$2 ~ /^(P|L)$/ {found=1} END {exit !found}'
}

root_path_integrity_ok() {
    local root_path
    local path_item
    local mode
    local owner

    root_path="$(su - root -c 'printf "%s\n" "$PATH"' 2>/dev/null)"
    [ -n "$root_path" ] || return 1

    grep -q -- "::" <<< "$root_path" && return 1
    grep -Pq -- ':\h*$' <<< "$root_path" && return 1
    grep -Pq -- '(^\h*|:)\.(:|\h*$)' <<< "$root_path" && return 1

    IFS=':' read -r -a root_path_items <<< "$root_path"
    for path_item in "${root_path_items[@]}"; do
        [ -d "$path_item" ] || return 1
        owner="$(stat -Lc '%U' "$path_item" 2>/dev/null)" || return 1
        [ "$owner" = "root" ] || return 1
        mode="$(stat -Lc '%a' "$path_item" 2>/dev/null)" || return 1
        [ $((8#$mode & 8#022)) -eq 0 ] || return 1
    done
}

root_umask_ok() {
    ! grep -Psiq -- '^\h*umask\h+((\d{1,2}(\d[^7]|[^2-7]\d)\b)|(u=[rwx]{1,3},)?(((g=[rx]?[rx]?w[rx]?[rx]?\b)(,o=[rwx]{1,3})?)|((g=[wrx]{1,3},)?o=[wrx]{1,3}\b)))' /root/.profile /root/.bashrc 2>/dev/null
}

uid_min() {
    awk '/^\s*UID_MIN/ {print $2; exit}' /etc/login.defs 2>/dev/null
}

valid_login_shells_regex() {
    awk -F/ '$NF != "nologin" && /^\// {gsub("/", "\\/"); print}' /etc/shells 2>/dev/null | paste -s -d '|' -
}

system_accounts_shells_ok() {
    local shell_regex
    local min_uid

    shell_regex="$(valid_login_shells_regex)"
    min_uid="$(uid_min)"
    [ -n "$shell_regex" ] && [[ "$min_uid" =~ ^[0-9]+$ ]] || return 1

    awk -v pat="^(${shell_regex})$" -v min_uid="$min_uid" -F: \
        '($1 !~ /^(root|halt|sync|shutdown|nfsnobody)$/ && ($3 < min_uid || $3 == 65534) && $NF ~ pat) {bad=1} END {exit bad}' \
        /etc/passwd 2>/dev/null
}

non_login_shell_accounts_locked() {
    local shell_regex
    local user

    shell_regex="$(valid_login_shells_regex)"
    [ -n "$shell_regex" ] || return 1

    while IFS= read -r user; do
        passwd -S "$user" 2>/dev/null | awk '$2 ~ /^L/ {locked=1} END {exit !locked}' || return 1
    done < <(awk -v pat="^(${shell_regex})$" -F: '($1 != "root" && $NF !~ pat) {print $1}' /etc/passwd 2>/dev/null)
}

shells_lacks_nologin() {
    ! grep -Psq -- '^\h*([^#\n\r]+)?/nologin\b' /etc/shells 2>/dev/null
}

tmout_file_ok() {
    file="$1"
    local value

    value="$(grep -Po -- '^([^#\n\r]+)?\bTMOUT=\K[0-9]+\b' "$file" 2>/dev/null | tail -n 1)"
    [[ "$value" =~ ^[0-9]+$ ]] || return 1
    [ "$value" -gt 0 ] && [ "$value" -le 900 ] || return 1
    grep -Pq -- '^\h*(typeset\h+-xr\h+TMOUT=[0-9]+|([^#\n\r]+)?\breadonly\h+TMOUT\b)' "$file" 2>/dev/null || return 1
    grep -Pq -- '^\h*(typeset\h+-xr\h+TMOUT=[0-9]+|([^#\n\r]+)?\bexport\b([^#\n\r]+\b)?TMOUT\b)' "$file" 2>/dev/null
}

default_shell_timeout_ok() {
    local found=0
    local file

    while IFS= read -r file; do
        found=1
        tmout_file_ok "$file" || return 1
    done < <(grep -Pls -- '^([^#\n\r]+)?\bTMOUT\b' /etc/*bashrc /etc/profile /etc/profile.d/*.sh 2>/dev/null)

    [ "$found" -eq 1 ]
}

numeric_umask_restrictive_027() {
    value="$1"

    value="${value#0}"
    value="${value#0}"
    [[ "$value" =~ ^[0-7]{3}$ ]] || return 1
    [ $((8#$value & 8#027)) -eq 8#027 ]
}

profile_d_umask_ok() {
    local value

    while IFS= read -r value; do
        numeric_umask_restrictive_027 "$value" && return 0
    done < <(grep -Phsi -- '^\h*umask\h+0?[0-7]{3}\b' /etc/profile.d/*.sh 2>/dev/null | awk '{print $2}')

    return 1
}

login_defs_umask_ok() {
    local value

    value="$(login_defs_value "UMASK")"
    numeric_umask_restrictive_027 "$value"
}

default_user_umask_ok() {
    profile_d_umask_ok && login_defs_umask_ok
}

audit_5_4_2_1() {
    control_id="5.4.2.1"
    title="Ensure root is the only UID 0 account"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if uid_zero_only_root; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_5_4_2_2() {
    control_id="5.4.2.2"
    title="Ensure root is the only GID 0 account"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if primary_gid_zero_ok; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_5_4_2_3() {
    control_id="5.4.2.3"
    title="Ensure group root is the only GID 0 group"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if gid_zero_only_root_group; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_5_4_2_4() {
    control_id="5.4.2.4"
    title="Ensure root account access is controlled"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if root_access_controlled; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_5_4_2_5() {
    control_id="5.4.2.5"
    title="Ensure root path integrity"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if root_path_integrity_ok; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_5_4_2_6() {
    control_id="5.4.2.6"
    title="Ensure root user umask is configured"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if root_umask_ok; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_5_4_2_7() {
    control_id="5.4.2.7"
    title="Ensure system accounts do not have a valid login shell"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if system_accounts_shells_ok; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_5_4_2_8() {
    control_id="5.4.2.8"
    title="Ensure accounts without a valid login shell are locked"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if non_login_shell_accounts_locked; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_5_4_3_1() {
    control_id="5.4.3.1"
    title="Ensure nologin is not listed in /etc/shells"
    applicability="l2-server,l2-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if shells_lacks_nologin; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_5_4_3_2() {
    control_id="5.4.3.2"
    title="Ensure default user shell timeout is configured"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if default_shell_timeout_ok; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_5_4_3_3() {
    control_id="5.4.3.3"
    title="Ensure default user umask is configured"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if default_user_umask_ok; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

journald_config_stream() {
    if command -v systemd-analyze >/dev/null 2>&1; then
        systemd-analyze cat-config systemd/journald.conf 2>/dev/null
    else
        [ -f /etc/systemd/journald.conf ] && printf '%s\n' /etc/systemd/journald.conf
        find /etc/systemd/journald.conf.d -type f -name '*.conf' -print 2>/dev/null | sort
    fi
}

journald_config_value() {
    option="$1"

    if command -v systemd-analyze >/dev/null 2>&1; then
        journald_config_stream | awk -v option="$option" '
            /^\s*\[Journal\]/ {in_journal=1; next}
            /^\s*\[/ {in_journal=0}
            in_journal && $0 !~ /^\s*(#|;)/ {
                split($0, parts, "=")
                key=parts[1]
                gsub(/^[ \t]+|[ \t]+$/, "", key)
                if (tolower(key) == tolower(option)) {
                    value=substr($0, index($0, "=") + 1)
                    gsub(/^[ \t]+|[ \t]+$/, "", value)
                    result=value
                }
            }
            END {if (result != "") print result}
        '
    else
        while IFS= read -r config_file; do
            awk -v option="$option" '
                /^\s*\[Journal\]/ {in_journal=1; next}
                /^\s*\[/ {in_journal=0}
                in_journal && $0 !~ /^\s*(#|;)/ {
                    split($0, parts, "=")
                    key=parts[1]
                    gsub(/^[ \t]+|[ \t]+$/, "", key)
                    if (tolower(key) == tolower(option)) {
                        value=substr($0, index($0, "=") + 1)
                        gsub(/^[ \t]+|[ \t]+$/, "", value)
                        result=value
                    }
                }
                END {if (result != "") print result}
            ' "$config_file" 2>/dev/null
        done < <(journald_config_stream) | tail -n 1
    fi
}

journald_option_equals() {
    option="$1"
    expected="$2"

    [ "$(journald_config_value "$option" | tr '[:upper:]' '[:lower:]')" = "$expected" ]
}

unit_active() {
    unit="$1"

    systemctl is-active "$unit" 2>/dev/null | grep -q '^active'
}

journal_remote_not_in_use() {
    ! systemctl is-enabled systemd-journal-remote.socket systemd-journal-remote.service 2>/dev/null | grep -Pq '^enabled' \
        && ! systemctl is-active systemd-journal-remote.socket systemd-journal-remote.service 2>/dev/null | grep -Pq '^active'
}

audit_6_1_1_1_1() {
    control_id="6.1.1.1.1"
    title="Ensure journald service is active"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if unit_active "systemd-journald.service"; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_6_1_1_1_2() {
    control_id="6.1.1.1.2"
    title="Ensure systemd-journal-remote service is not in use"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if journal_remote_not_in_use; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_6_1_1_1_3() {
    control_id="6.1.1.1.3"
    title="Ensure journald is configured to send logs to rsyslog"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if ! unit_active "rsyslog.service"; then
        na_control "$control_id" "$title"
    elif unit_active "systemd-journald.service" && journald_option_equals "ForwardToSyslog" "yes"; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_6_1_1_1_4() {
    control_id="6.1.1.1.4"
    title="Ensure journald log file access is configured"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0
    manual_control "$control_id" "$title"
}

audit_6_1_1_1_5() {
    control_id="6.1.1.1.5"
    title="Ensure journald log file rotation is configured"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0
    manual_control "$control_id" "$title"
}

audit_6_1_1_1_6() {
    control_id="6.1.1.1.6"
    title="Ensure journald Storage is configured"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if journald_option_equals "Storage" "persistent"; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_6_1_1_1_7() {
    control_id="6.1.1.1.7"
    title="Ensure journald Compress is configured"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if journald_option_equals "Compress" "yes"; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

rsyslog_installed() {
    package_installed "rsyslog"
}

rsyslog_required() {
    rsyslog_installed \
        || unit_enabled_or_active "rsyslog.service" \
        || journald_option_equals "ForwardToSyslog" "yes"
}

rsyslog_config_files() {
    [ -f /etc/rsyslog.conf ] && printf '%s\n' /etc/rsyslog.conf
    find /etc/rsyslog.d -type f -name '*.conf' -print 2>/dev/null
}

grep_rsyslog_config() {
    pattern="$1"

    rsyslog_config_files | xargs -r grep -Psi -- "$pattern" 2>/dev/null
}

rsyslog_file_create_mode_ok() {
    grep_rsyslog_config '^\h*\$FileCreateMode\h+0[0246][024]0\b' | grep -q .
}

rsyslog_not_receiving_remote_logs() {
    ! grep_rsyslog_config '^\h*module\(load="?imtcp"?\)' | grep -q . \
        && ! grep_rsyslog_config '^\h*input\(type="?imtcp"?\b' | grep -q . \
        && ! grep_rsyslog_config '^\h*\$ModLoad\h+imtcp\b' | grep -q . \
        && ! grep_rsyslog_config '^\h*\$InputTCPServerRun\b' | grep -q .
}

rsyslog_forwarding_uses_gtls() {
    grep_rsyslog_config '^\h*StreamDriver="?gtls"?' | grep -q . \
        || grep_rsyslog_config '\bStreamDriver="?gtls"?' | grep -q .
}

audit_6_1_2_1() {
    control_id="6.1.2.1"
    title="Ensure rsyslog is installed"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if rsyslog_installed; then
        pass_control "$control_id" "$title"
    elif journald_option_equals "ForwardToSyslog" "yes" || unit_enabled_or_active "rsyslog.service"; then
        fail_control "$control_id" "$title"
    else
        na_control "$control_id" "$title"
    fi
}

audit_6_1_2_2() {
    control_id="6.1.2.2"
    title="Ensure rsyslog service is enabled and active"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if ! rsyslog_required; then
        na_control "$control_id" "$title"
    elif rsyslog_installed && unit_enabled_and_active "rsyslog.service"; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_6_1_2_3() {
    control_id="6.1.2.3"
    title="Ensure rsyslog log file creation mode is configured"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if ! rsyslog_required; then
        na_control "$control_id" "$title"
    elif ! rsyslog_installed; then
        na_control "$control_id" "$title"
    elif rsyslog_file_create_mode_ok; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_6_1_2_4() {
    control_id="6.1.2.4"
    title="Ensure rsyslog logging is configured"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if ! rsyslog_required; then
        na_control "$control_id" "$title"
    else
        manual_control "$control_id" "$title"
    fi
}

audit_6_1_2_5() {
    control_id="6.1.2.5"
    title="Ensure rsyslog is configured to send logs to a remote log host"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if ! rsyslog_required; then
        na_control "$control_id" "$title"
    else
        manual_control "$control_id" "$title"
    fi
}

audit_6_1_2_6() {
    control_id="6.1.2.6"
    title="Ensure rsyslog is not configured to receive logs from a remote client"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if ! rsyslog_required; then
        na_control "$control_id" "$title"
    elif ! rsyslog_installed; then
        na_control "$control_id" "$title"
    elif rsyslog_not_receiving_remote_logs; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_6_1_2_7() {
    control_id="6.1.2.7"
    title="Ensure logrotate is configured"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if ! rsyslog_required; then
        na_control "$control_id" "$title"
    else
        manual_control "$control_id" "$title"
    fi
}

audit_6_1_2_8() {
    control_id="6.1.2.8"
    title="Ensure rsyslog-gnutls is installed"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if ! rsyslog_required; then
        na_control "$control_id" "$title"
    elif package_installed "rsyslog-gnutls"; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_6_1_2_9() {
    control_id="6.1.2.9"
    title="Ensure rsyslog forwarding uses gtls"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if ! rsyslog_required; then
        na_control "$control_id" "$title"
    elif ! rsyslog_installed; then
        na_control "$control_id" "$title"
    elif rsyslog_forwarding_uses_gtls; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_6_1_2_10() {
    control_id="6.1.2.10"
    title="Ensure rsyslog CA certificates are configured"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if ! rsyslog_required; then
        na_control "$control_id" "$title"
    else
        manual_control "$control_id" "$title"
    fi
}

logfile_access_expected() {
    path="$1"
    local basename
    local dirname
    local mode
    local owner
    local group
    local perm_mask
    local allowed_user
    local allowed_group
    local user_shell

    basename="$(basename "$path")"
    dirname="$(dirname "$path")"
    mode="$(stat -Lc '%a' "$path" 2>/dev/null)" || return 1
    owner="$(stat -Lc '%U' "$path" 2>/dev/null)" || return 1
    group="$(stat -Lc '%G' "$path" 2>/dev/null)" || return 1

    if grep -Pq -- '/(apt)\h*$' <<< "$dirname"; then
        perm_mask="0133"
        allowed_user="^(root)$"
        allowed_group="^(root|adm)$"
    else
        case "$basename" in
            lastlog|lastlog.*|wtmp|wtmp.*|wtmp-*|btmp|btmp.*|btmp-*|README)
                perm_mask="0113"
                allowed_user="^(root)$"
                allowed_group="^(root|utmp)$"
                ;;
            cloud-init.log*|localmessages*|waagent.log*)
                perm_mask="0133"
                allowed_user="^(root|syslog)$"
                allowed_group="^(root|adm)$"
                ;;
            secure|secure.*|secure-*|auth.log|syslog|messages)
                perm_mask="0137"
                allowed_user="^(root|syslog)$"
                allowed_group="^(root|adm)$"
                ;;
            SSSD|sssd)
                perm_mask="0117"
                allowed_user="^(root|SSSD)$"
                allowed_group="^(root|SSSD)$"
                ;;
            gdm|gdm3)
                perm_mask="0117"
                allowed_user="^(root)$"
                allowed_group="^(root|gdm|gdm3)$"
                ;;
            *.journal|*.journal~)
                perm_mask="0137"
                allowed_user="^(root)$"
                allowed_group="^(root|systemd-journal)$"
                ;;
            *)
                perm_mask="0137"
                allowed_user="^(root|syslog)$"
                allowed_group="^(root|adm)$"
                user_shell="$(awk -F: -v user="$owner" '$1 == user {print $7; exit}' /etc/passwd 2>/dev/null)"
                if [ "$owner" = "root" ] || ! grep -Pq -- "^\h*${user_shell}\b" /etc/shells 2>/dev/null; then
                    allowed_user="^(root|syslog|${owner})$"
                    allowed_group="^(root|adm|${group})$"
                fi
                ;;
        esac
    fi

    [ $((8#$mode & 8#$perm_mask)) -eq 0 ] \
        && grep -Pq -- "$allowed_user" <<< "$owner" \
        && grep -Pq -- "$allowed_group" <<< "$group"
}

var_log_files_access_ok() {
    local log_file

    [ -d /var/log ] || return 1

    while IFS= read -r -d '' log_file; do
        logfile_access_expected "$log_file" || return 1
    done < <(find -L /var/log -type f \( -perm /0137 -o ! -user root -o ! -group root \) -print0 2>/dev/null)
}

audit_6_1_3_1() {
    control_id="6.1.3.1"
    title="Ensure access to all logfiles has been configured"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if var_log_files_access_ok; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

auditd_installed() {
    package_installed "auditd" && package_installed "audispd-plugins"
}

grub_linux_lines() {
    find /boot -type f -name 'grub.cfg' -exec grep -Ph -- '^\h*linux' {} + 2>/dev/null
}

grub_linux_lines_have() {
    pattern="$1"

    [ -n "$(grub_linux_lines)" ] || return 1
    ! grub_linux_lines | grep -Pvq "$pattern"
}

auditd_conf_value() {
    key="$1"

    awk -F= -v key="$key" '
        $1 ~ "^[ \t]*" key "[ \t]*$" {
            value=$2
            gsub(/^[ \t]+|[ \t]+$/, "", value)
            result=value
        }
        END {if (result != "") print result}
    ' /etc/audit/auditd.conf 2>/dev/null
}

auditd_conf_numeric_positive() {
    key="$1"
    local value

    value="$(auditd_conf_value "$key")"
    [[ "$value" =~ ^[0-9]+$ ]] && [ "$value" -gt 0 ]
}

auditd_conf_value_matches() {
    key="$1"
    regex="$2"
    local value

    value="$(auditd_conf_value "$key")"
    grep -Eiq "^(${regex})$" <<< "$value"
}

audit_6_2_1_1() {
    control_id="6.2.1.1"
    title="Ensure auditd packages are installed"
    applicability="l2-server,l2-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if auditd_installed; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_6_2_1_2() {
    control_id="6.2.1.2"
    title="Ensure auditd service is enabled and active"
    applicability="l2-server,l2-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if ! auditd_installed; then
        na_control "$control_id" "$title"
    elif unit_enabled_and_active "auditd.service"; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_6_2_1_3() {
    control_id="6.2.1.3"
    title="Ensure auditing for processes that start prior to auditd is enabled"
    applicability="l2-server,l2-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if grub_linux_lines_have '\baudit=1\b'; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_6_2_1_4() {
    control_id="6.2.1.4"
    title="Ensure audit_backlog_limit is configured"
    applicability="l2-server,l2-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if grub_linux_lines_have '\baudit_backlog_limit=[0-9]+\b'; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_6_2_2_1() {
    control_id="6.2.2.1"
    title="Ensure audit log storage size is configured"
    applicability="l2-server,l2-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if ! auditd_installed; then
        na_control "$control_id" "$title"
    elif auditd_conf_numeric_positive "max_log_file"; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_6_2_2_2() {
    control_id="6.2.2.2"
    title="Ensure audit logs are not automatically deleted"
    applicability="l2-server,l2-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if ! auditd_installed; then
        na_control "$control_id" "$title"
    elif auditd_conf_value_matches "max_log_file_action" "keep_logs"; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_6_2_2_3() {
    control_id="6.2.2.3"
    title="Ensure system is disabled when audit logs are full"
    applicability="l2-server,l2-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if ! auditd_installed; then
        na_control "$control_id" "$title"
    elif auditd_conf_value_matches "disk_full_action" "halt|single" \
        && auditd_conf_value_matches "disk_error_action" "syslog|single|halt"; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_6_2_2_4() {
    control_id="6.2.2.4"
    title="Ensure system warns when audit logs are low on space"
    applicability="l2-server,l2-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if ! auditd_installed; then
        na_control "$control_id" "$title"
    elif auditd_conf_value_matches "space_left_action" "email|exec|single|halt" \
        && auditd_conf_value_matches "admin_space_left_action" "single|halt"; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_rules_disk() {
    cat /etc/audit/rules.d/*.rules 2>/dev/null
}

audit_rules_running() {
    auditctl -l 2>/dev/null
}

audit_rules_source_has() {
    source_name="$1"
    pattern="$2"

    case "$source_name" in
        disk) audit_rules_disk | grep -Pq -- "$pattern" ;;
        running) audit_rules_running | grep -Pq -- "$pattern" ;;
    esac
}

audit_rule_present_in_both() {
    pattern="$1"

    audit_rules_source_has running "$pattern" && audit_rules_source_has disk "$pattern"
}

audit_watch_present_in_both() {
    watched_path="$1"
    key="$2"
    local escaped_path

    escaped_path="$(printf '%s\n' "$watched_path" | sed 's/[.[\*^$()+?{}|\\]/\\&/g')"
    audit_rule_present_in_both "^\h*-w\h+${escaped_path}\h+-p\h+wa\h+(-k\h+${key}|-F\h+key=${key})\b"
}

audit_syscall_rule_present_in_both() {
    syscall_regex="$1"
    key="$2"

    audit_rule_present_in_both "^\h*-a\h+always,exit\b.*${syscall_regex}.*(-k\h+${key}|-F\h+key=${key})\b"
}

audit_syscall_arch_rule_present_in_both() {
    arch="$1"
    syscall_regex="$2"
    key="$3"

    audit_rule_present_in_both "^\h*-a\h+always,exit\b.*-F\h+arch=${arch}\b.*${syscall_regex}.*(-k\h+${key}|-F\h+key=${key})\b"
}

audit_auid_syscall_arch_rule_present_in_both() {
    arch="$1"
    syscall_regex="$2"
    key="$3"
    local min_uid
    local source_name

    min_uid="$(uid_min)"
    [[ "$min_uid" =~ ^[0-9]+$ ]] || return 1

    for source_name in running disk; do
        case "$source_name" in
            running)
                audit_rules_running | awk -v arch="$arch" -v syscall="$syscall_regex" -v min_uid="$min_uid" -v key="$key" '
                    $0 ~ /^ *-a *always,exit/ &&
                    $0 ~ "-F *arch=" arch &&
                    $0 ~ "-F *auid>=" min_uid &&
                    ($0 ~ "-F *auid!=unset" || $0 ~ "-F *auid!=-1" || $0 ~ "-F *auid!=4294967295") &&
                    $0 ~ syscall &&
                    ($0 ~ "-k *" key "\\b" || $0 ~ "-F *key=" key "\\b") {found=1}
                    END {exit !found}
                ' || return 1
                ;;
            disk)
                audit_rules_disk | awk -v arch="$arch" -v syscall="$syscall_regex" -v min_uid="$min_uid" -v key="$key" '
                    $0 ~ /^ *-a *always,exit/ &&
                    $0 ~ "-F *arch=" arch &&
                    $0 ~ "-F *auid>=" min_uid &&
                    ($0 ~ "-F *auid!=unset" || $0 ~ "-F *auid!=-1" || $0 ~ "-F *auid!=4294967295") &&
                    $0 ~ syscall &&
                    ($0 ~ "-k *" key "\\b" || $0 ~ "-F *key=" key "\\b") {found=1}
                    END {exit !found}
                ' || return 1
                ;;
        esac
    done
}

audit_path_exec_rule_present_in_both() {
    executable_path="$1"
    key="$2"
    local min_uid
    local escaped_path

    min_uid="$(uid_min)"
    [[ "$min_uid" =~ ^[0-9]+$ ]] || return 1
    escaped_path="$(printf '%s\n' "$executable_path" | sed 's/[.[\*^$()+?{}|\\]/\\&/g')"
    audit_rule_present_in_both "^\h*-a\h+always,exit\b.*-F\h+path=${escaped_path}\b.*-F\h+perm=x\b.*-F\h+auid>=${min_uid}\b.*(-F\h+auid!=unset|-F\h+auid!=-1|-F\h+auid!=4294967295)\b.*(-k\h+${key}|-F\h+key=${key})\b"
}

sudo_logfile_path() {
    grep_sudoers '^\h*Defaults\h+([^#]+,\h*)?logfile\h*=\h*("|'"'"')?\H+("|'"'"')?(,\h*\H+\h*)*\h*(#.*)?$' \
        | sed -E 's/.*logfile[[:space:]]*=[[:space:]]*["'\'']?([^,"'\'']+).*/\1/' \
        | head -n 1
}

privileged_commands_audited() {
    local min_uid
    local filesystem_types
    local partition
    local privileged

    min_uid="$(uid_min)"
    [[ "$min_uid" =~ ^[0-9]+$ ]] || return 1
    filesystem_types="$(awk '/nodev/ {print $2}' /proc/filesystems 2>/dev/null | paste -sd, -)"
    [ -n "$filesystem_types" ] || return 1

    while IFS= read -r partition; do
        while IFS= read -r privileged; do
            audit_path_exec_rule_present_in_both "$privileged" "privileged" || return 1
        done < <(find "$partition" -xdev -perm /6000 -type f 2>/dev/null)
    done < <(findmnt -n -l -k -it "$filesystem_types" 2>/dev/null | awk '$0 !~ /noexec|nosuid/ {print $1}')
}

audit_6_2_3_dependency_or_na() {
    control_id="$1"
    title="$2"

    if ! auditd_installed; then
        na_control "$control_id" "$title"
        return 0
    fi
    return 1
}

audit_simple_audit_rule_control() {
    control_id="$1"
    title="$2"
    pattern="$3"
    applicability="l2-server,l2-workstation"

    should_run_control "$control_id" "$applicability" || return 0
    audit_6_2_3_dependency_or_na "$control_id" "$title" && return 0

    if audit_rule_present_in_both "$pattern"; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_watch_control() {
    control_id="$1"
    title="$2"
    key="$3"
    shift 3
    applicability="l2-server,l2-workstation"
    local watched_path

    should_run_control "$control_id" "$applicability" || return 0
    audit_6_2_3_dependency_or_na "$control_id" "$title" && return 0

    for watched_path in "$@"; do
        audit_watch_present_in_both "$watched_path" "$key" || { fail_control "$control_id" "$title"; return 0; }
    done
    pass_control "$control_id" "$title"
}

audit_6_2_3_1() {
    audit_watch_control "6.2.3.1" "Ensure changes to system administration scope (sudoers) is collected" "scope" "/etc/sudoers" "/etc/sudoers.d"
}

audit_6_2_3_2() {
    control_id="6.2.3.2"
    title="Ensure actions as another user are always logged"
    applicability="l2-server,l2-workstation"
    should_run_control "$control_id" "$applicability" || return 0
    audit_6_2_3_dependency_or_na "$control_id" "$title" && return 0

    if audit_syscall_arch_rule_present_in_both "b64" "execve" "user_emulation" \
        && audit_syscall_arch_rule_present_in_both "b32" "execve" "user_emulation"; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_6_2_3_3() {
    control_id="6.2.3.3"
    title="Ensure events that modify the sudo log file are collected"
    applicability="l2-server,l2-workstation"
    local sudo_log

    should_run_control "$control_id" "$applicability" || return 0
    audit_6_2_3_dependency_or_na "$control_id" "$title" && return 0

    sudo_log="$(sudo_logfile_path)"
    if [ -n "$sudo_log" ] && audit_watch_present_in_both "$sudo_log" "sudo_log_file"; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_6_2_3_4() {
    control_id="6.2.3.4"
    title="Ensure events that modify date and time information are collected"
    applicability="l2-server,l2-workstation"
    should_run_control "$control_id" "$applicability" || return 0
    audit_6_2_3_dependency_or_na "$control_id" "$title" && return 0

    if audit_syscall_arch_rule_present_in_both "b64" "(adjtimex|settimeofday)" "time-change" \
        && audit_syscall_arch_rule_present_in_both "b32" "(adjtimex|settimeofday)" "time-change" \
        && audit_syscall_arch_rule_present_in_both "b64" "clock_settime" "time-change" \
        && audit_syscall_arch_rule_present_in_both "b32" "clock_settime" "time-change" \
        && audit_watch_present_in_both "/etc/localtime" "time-change"; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_6_2_3_5() {
    control_id="6.2.3.5"
    title="Ensure events that modify sethostname and setdomainname are collected"
    applicability="l2-server,l2-workstation"
    should_run_control "$control_id" "$applicability" || return 0
    audit_6_2_3_dependency_or_na "$control_id" "$title" && return 0

    if audit_syscall_arch_rule_present_in_both "b64" "(sethostname|setdomainname)" "system-locale" \
        && audit_syscall_arch_rule_present_in_both "b32" "(sethostname|setdomainname)" "system-locale"; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_6_2_3_6() { audit_watch_control "6.2.3.6" "Ensure events that modify /etc/issue and /etc/issue.net are collected" "system-locale" "/etc/issue" "/etc/issue.net"; }
audit_6_2_3_7() { audit_watch_control "6.2.3.7" "Ensure events that modify /etc/hosts and /etc/hostname are collected" "system-locale" "/etc/hosts" "/etc/hostname"; }
audit_6_2_3_8() { audit_watch_control "6.2.3.8" "Ensure events that modify /etc/network and /etc/networks are collected" "system-locale" "/etc/networks" "/etc/network"; }
audit_6_2_3_9() { audit_watch_control "6.2.3.9" "Ensure events that modify /etc/netplan are collected" "system-locale" "/etc/netplan"; }

audit_6_2_3_10() {
    control_id="6.2.3.10"
    title="Ensure use of privileged commands are collected"
    applicability="l2-server,l2-workstation"
    should_run_control "$control_id" "$applicability" || return 0
    audit_6_2_3_dependency_or_na "$control_id" "$title" && return 0

    if privileged_commands_audited; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_6_2_3_11() { audit_watch_control "6.2.3.11" "Ensure events that modify /etc/group information are collected" "identity" "/etc/group"; }
audit_6_2_3_12() { audit_watch_control "6.2.3.12" "Ensure events that modify /etc/passwd information are collected" "identity" "/etc/passwd"; }
audit_6_2_3_13() { audit_watch_control "6.2.3.13" "Ensure events that modify /etc/shadow and /etc/gshadow are collected" "identity" "/etc/gshadow" "/etc/shadow"; }
audit_6_2_3_14() { audit_watch_control "6.2.3.14" "Ensure events that modify /etc/security/opasswd are collected" "identity" "/etc/security/opasswd"; }
audit_6_2_3_15() { audit_watch_control "6.2.3.15" "Ensure events that modify /etc/nsswitch.conf file are collected" "identity" "/etc/nsswitch.conf"; }
audit_6_2_3_16() { audit_watch_control "6.2.3.16" "Ensure events that modify /etc/pam.conf and /etc/pam.d/ information are collected" "identity" "/etc/pam.conf" "/etc/pam.d"; }

audit_6_2_3_17() {
    control_id="6.2.3.17"
    title="Ensure unsuccessful file access attempts are collected"
    applicability="l2-server,l2-workstation"
    should_run_control "$control_id" "$applicability" || return 0
    audit_6_2_3_dependency_or_na "$control_id" "$title" && return 0

    if audit_auid_syscall_arch_rule_present_in_both "b64" "(creat|open|openat|truncate|ftruncate)" "access" \
        && audit_auid_syscall_arch_rule_present_in_both "b32" "(creat|open|openat|truncate|ftruncate)" "access" \
        && audit_rule_present_in_both "EACCES" \
        && audit_rule_present_in_both "EPERM"; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_6_2_3_18() {
    control_id="6.2.3.18"
    title="Ensure discretionary access control permission modification events are collected"
    applicability="l2-server,l2-workstation"
    should_run_control "$control_id" "$applicability" || return 0
    audit_6_2_3_dependency_or_na "$control_id" "$title" && return 0

    if audit_auid_syscall_arch_rule_present_in_both "b64" "(chmod|fchmod|fchmodat|chown|fchown|fchownat|lchown|setxattr|lsetxattr|fsetxattr|removexattr|lremovexattr|fremovexattr)" "perm_mod" \
        && audit_auid_syscall_arch_rule_present_in_both "b32" "(chmod|fchmod|fchmodat|chown|fchown|fchownat|lchown|setxattr|lsetxattr|fsetxattr|removexattr|lremovexattr|fremovexattr)" "perm_mod"; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_6_2_3_19() {
    control_id="6.2.3.19"
    title="Ensure successful file system mounts are collected"
    applicability="l2-server,l2-workstation"
    should_run_control "$control_id" "$applicability" || return 0
    audit_6_2_3_dependency_or_na "$control_id" "$title" && return 0

    if audit_auid_syscall_arch_rule_present_in_both "b64" "mount" "mounts" \
        && audit_auid_syscall_arch_rule_present_in_both "b32" "mount" "mounts"; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_6_2_3_20() { audit_watch_control "6.2.3.20" "Ensure session initiation information is collected" "session" "/var/run/utmp" "/var/log/wtmp" "/var/log/btmp"; }
audit_6_2_3_21() { audit_watch_control "6.2.3.21" "Ensure login and logout events are collected" "logins" "/var/log/lastlog" "/var/run/faillock"; }

audit_6_2_3_22() {
    control_id="6.2.3.22"
    title="Ensure file deletion events by users are collected"
    applicability="l2-server,l2-workstation"
    should_run_control "$control_id" "$applicability" || return 0
    audit_6_2_3_dependency_or_na "$control_id" "$title" && return 0

    if audit_auid_syscall_arch_rule_present_in_both "b64" "(unlink|unlinkat|rename|renameat|renameat2)" "delete" \
        && audit_auid_syscall_arch_rule_present_in_both "b32" "(unlink|unlinkat|rename|renameat|renameat2)" "delete"; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_6_2_3_23() { audit_watch_control "6.2.3.23" "Ensure events that modify the system's Mandatory Access Controls are collected" "MAC-policy" "/etc/apparmor/" "/etc/apparmor.d/"; }
audit_6_2_3_24() { audit_path_command_control "6.2.3.24" "Ensure successful and unsuccessful attempts to use the chcon command are collected" "/usr/bin/chcon" "perm_chng"; }
audit_6_2_3_25() { audit_path_command_control "6.2.3.25" "Ensure successful and unsuccessful attempts to use the setfacl command are collected" "/usr/bin/setfacl" "perm_chng"; }
audit_6_2_3_26() { audit_path_command_control "6.2.3.26" "Ensure successful and unsuccessful attempts to use the chacl command are collected" "/usr/bin/chacl" "perm_chng"; }
audit_6_2_3_27() { audit_path_command_control "6.2.3.27" "Ensure successful and unsuccessful attempts to use the usermod command are collected" "/usr/sbin/usermod" "usermod"; }

audit_path_command_control() {
    control_id="$1"
    title="$2"
    executable_path="$3"
    key="$4"
    applicability="l2-server,l2-workstation"

    should_run_control "$control_id" "$applicability" || return 0
    audit_6_2_3_dependency_or_na "$control_id" "$title" && return 0

    if audit_path_exec_rule_present_in_both "$executable_path" "$key"; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_6_2_3_28() {
    control_id="6.2.3.28"
    title="Ensure kernel module loading unloading and modification is collected"
    applicability="l2-server,l2-workstation"
    should_run_control "$control_id" "$applicability" || return 0
    audit_6_2_3_dependency_or_na "$control_id" "$title" && return 0

    if audit_auid_syscall_arch_rule_present_in_both "b64" "(init_module|finit_module|delete_module|create_module|query_module)" "kernel_modules" \
        && audit_auid_syscall_arch_rule_present_in_both "b32" "(init_module|finit_module|delete_module|create_module|query_module)" "kernel_modules" \
        && audit_path_exec_rule_present_in_both "/usr/bin/kmod" "kernel_modules"; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_6_2_3_29() {
    control_id="6.2.3.29"
    title="Ensure the audit configuration is immutable"
    applicability="l2-server,l2-workstation"
    should_run_control "$control_id" "$applicability" || return 0
    audit_6_2_3_dependency_or_na "$control_id" "$title" && return 0

    if grep -Ph -- '^\h*-e\h+2\b' /etc/audit/rules.d/*.rules 2>/dev/null | tail -n 1 | grep -Pq -- '^\h*-e\h+2\b'; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_6_2_3_30() {
    control_id="6.2.3.30"
    title="Ensure the running and on disk configuration is the same"
    applicability="l2-server,l2-workstation"

    should_run_control "$control_id" "$applicability" || return 0
    manual_control "$control_id" "$title"
}

audit_log_file_path() {
    auditd_conf_value "log_file"
}

audit_log_directory() {
    local log_file

    log_file="$(audit_log_file_path)"
    [ -n "$log_file" ] || return 1
    dirname "$log_file"
}

audit_log_directory_exists() {
    local log_dir

    log_dir="$(audit_log_directory)" || return 1
    [ -d "$log_dir" ]
}

audit_log_directory_mode_ok() {
    local log_dir

    log_dir="$(audit_log_directory)" || return 1
    [ -d "$log_dir" ] || return 1
    path_mode_has_no_bits "$log_dir" "027"
}

audit_log_files_mode_ok() {
    local log_dir

    log_dir="$(audit_log_directory)" || return 1
    [ -d "$log_dir" ] || return 1
    [ -z "$(find "$log_dir" -maxdepth 1 -type f -perm /0137 -print -quit 2>/dev/null)" ]
}

audit_log_files_owner_ok() {
    local log_dir

    log_dir="$(audit_log_directory)" || return 1
    [ -d "$log_dir" ] || return 1
    [ -z "$(find "$log_dir" -maxdepth 1 -type f ! -user root -print -quit 2>/dev/null)" ]
}

audit_log_group_config_ok() {
    auditd_conf_value_matches "log_group" "root|adm"
}

audit_log_files_group_ok() {
    local log_dir

    log_dir="$(audit_log_directory)" || return 1
    [ -d "$log_dir" ] || return 1
    [ -z "$(find -L "$log_dir" -maxdepth 1 -not -path "$log_dir/lost+found" -type f \( ! -group root -a ! -group adm \) -print -quit 2>/dev/null)" ]
}

audit_config_files_bad_access() {
    find /etc/audit -type f \( -name '*.conf' -o -name '*.rules' \) "$@" -print -quit 2>/dev/null
}

audit_config_files_mode_ok() {
    [ -z "$(audit_config_files_bad_access -perm /0137)" ]
}

audit_config_files_owner_ok() {
    [ -z "$(audit_config_files_bad_access ! -user root)" ]
}

audit_config_files_group_ok() {
    [ -z "$(audit_config_files_bad_access ! -group root)" ]
}

audit_tools() {
    printf '%s\n' /sbin/auditctl /sbin/aureport /sbin/ausearch /sbin/autrace /sbin/auditd /sbin/augenrules
}

audit_tools_exist() {
    local audit_tool

    while IFS= read -r audit_tool; do
        [ -e "$audit_tool" ] || return 1
    done < <(audit_tools)
}

audit_tools_mode_ok() {
    local audit_tool

    audit_tools_exist || return 1
    while IFS= read -r audit_tool; do
        path_mode_has_no_bits "$audit_tool" "022" || return 1
    done < <(audit_tools)
}

audit_tools_owner_ok() {
    local audit_tool

    audit_tools_exist || return 1
    while IFS= read -r audit_tool; do
        [ "$(stat -Lc '%U' "$audit_tool" 2>/dev/null)" = "root" ] || return 1
    done < <(audit_tools)
}

audit_tools_group_ok() {
    local audit_tool

    audit_tools_exist || return 1
    while IFS= read -r audit_tool; do
        [ "$(stat -Lc '%G' "$audit_tool" 2>/dev/null)" = "root" ] || return 1
    done < <(audit_tools)
}

audit_6_2_4_dependency_or_na() {
    control_id="$1"
    title="$2"

    if ! auditd_installed; then
        na_control "$control_id" "$title"
        return 0
    fi
    return 1
}

audit_6_2_4_1() {
    control_id="6.2.4.1"
    title="Ensure the audit log file directory mode is configured"
    applicability="l2-server,l2-workstation"

    should_run_control "$control_id" "$applicability" || return 0
    audit_6_2_4_dependency_or_na "$control_id" "$title" && return 0

    if audit_log_directory_mode_ok; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_6_2_4_2() {
    control_id="6.2.4.2"
    title="Ensure audit log files mode is configured"
    applicability="l2-server,l2-workstation"

    should_run_control "$control_id" "$applicability" || return 0
    audit_6_2_4_dependency_or_na "$control_id" "$title" && return 0

    if audit_log_files_mode_ok; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_6_2_4_3() {
    control_id="6.2.4.3"
    title="Ensure audit log files owner is configured"
    applicability="l2-server,l2-workstation"

    should_run_control "$control_id" "$applicability" || return 0
    audit_6_2_4_dependency_or_na "$control_id" "$title" && return 0

    if audit_log_files_owner_ok; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_6_2_4_4() {
    control_id="6.2.4.4"
    title="Ensure audit log files group owner is configured"
    applicability="l2-server,l2-workstation"

    should_run_control "$control_id" "$applicability" || return 0
    audit_6_2_4_dependency_or_na "$control_id" "$title" && return 0

    if audit_log_group_config_ok && audit_log_files_group_ok; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_6_2_4_5() {
    control_id="6.2.4.5"
    title="Ensure audit configuration files mode is configured"
    applicability="l2-server,l2-workstation"

    should_run_control "$control_id" "$applicability" || return 0
    audit_6_2_4_dependency_or_na "$control_id" "$title" && return 0

    if audit_config_files_mode_ok; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_6_2_4_6() {
    control_id="6.2.4.6"
    title="Ensure audit configuration files owner is configured"
    applicability="l2-server,l2-workstation"

    should_run_control "$control_id" "$applicability" || return 0
    audit_6_2_4_dependency_or_na "$control_id" "$title" && return 0

    if audit_config_files_owner_ok; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_6_2_4_7() {
    control_id="6.2.4.7"
    title="Ensure audit configuration files group owner is configured"
    applicability="l2-server,l2-workstation"

    should_run_control "$control_id" "$applicability" || return 0
    audit_6_2_4_dependency_or_na "$control_id" "$title" && return 0

    if audit_config_files_group_ok; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_6_2_4_8() {
    control_id="6.2.4.8"
    title="Ensure audit tools mode is configured"
    applicability="l2-server,l2-workstation"

    should_run_control "$control_id" "$applicability" || return 0
    audit_6_2_4_dependency_or_na "$control_id" "$title" && return 0

    if audit_tools_mode_ok; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_6_2_4_9() {
    control_id="6.2.4.9"
    title="Ensure audit tools owner is configured"
    applicability="l2-server,l2-workstation"

    should_run_control "$control_id" "$applicability" || return 0
    audit_6_2_4_dependency_or_na "$control_id" "$title" && return 0

    if audit_tools_owner_ok; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_6_2_4_10() {
    control_id="6.2.4.10"
    title="Ensure audit tools group owner is configured"
    applicability="l2-server,l2-workstation"

    should_run_control "$control_id" "$applicability" || return 0
    audit_6_2_4_dependency_or_na "$control_id" "$title" && return 0

    if audit_tools_group_ok; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

aide_installed() {
    package_installed "aide" && package_installed "aide-common"
}

aide_daily_check_configured() {
    local timer_enabled
    local service_enabled

    timer_enabled="$(systemctl is-enabled dailyaidecheck.timer 2>/dev/null)" || return 1
    service_enabled="$(systemctl is-enabled dailyaidecheck.service 2>/dev/null)" || return 1

    [ "$timer_enabled" = "enabled" ] || return 1
    case "$service_enabled" in
        static|enabled) ;;
        *) return 1 ;;
    esac

    [ "$(systemctl is-active dailyaidecheck.timer 2>/dev/null)" = "active" ]
}

aide_command() {
    command -v aide 2>/dev/null
}

aide_config_files() {
    find -L /etc -type f -name 'aide.conf' -print 2>/dev/null
}

aide_output_has_option() {
    local output="$1"
    local option="$2"

    printf '%s\n' "$output" | grep -Eq "(^|[[:space:]+])${option}([[:space:]+]|$)"
}

aide_audit_tool_integrity_ok() {
    local aide_cmd
    local tool_dir
    local tool
    local tool_path
    local output
    local option
    local config_files

    aide_cmd="$(aide_command)" || return 1
    [ -x "$aide_cmd" ] || return 1
    tool_dir="$(readlink -f /sbin 2>/dev/null)" || return 1
    config_files="$(aide_config_files)"
    [ -n "$config_files" ] || return 1

    for tool in auditctl auditd ausearch aureport autrace augenrules; do
        tool_path="$tool_dir/$tool"
        [ -f "$tool_path" ] || continue
        output="$("$aide_cmd" --config $config_files -p "f:$tool_path" 2>/dev/null)" || return 1
        for option in p i n u g s b acl xattrs sha512; do
            aide_output_has_option "$output" "$option" || return 1
        done
    done
}

audit_6_3_1() {
    control_id="6.3.1"
    title="Ensure AIDE is installed"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if aide_installed; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_6_3_2() {
    control_id="6.3.2"
    title="Ensure filesystem integrity is regularly checked"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if ! aide_installed; then
        na_control "$control_id" "$title"
    elif aide_daily_check_configured; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_6_3_3() {
    control_id="6.3.3"
    title="Ensure cryptographic mechanisms are used to protect the integrity of audit tools"
    applicability="l2-server,l2-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if ! aide_installed; then
        na_control "$control_id" "$title"
    elif aide_audit_tool_integrity_ok; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

file_access_ok() {
    local path="$1"
    local disallowed_mask="$2"
    local allowed_group_pattern="$3"
    local missing_ok="${4:-0}"
    local owner
    local group

    if [ ! -e "$path" ]; then
        [ "$missing_ok" -eq 1 ]
        return
    fi

    owner="$(stat -Lc '%U' "$path" 2>/dev/null)" || return 1
    group="$(stat -Lc '%G' "$path" 2>/dev/null)" || return 1
    [ "$owner" = "root" ] || return 1
    printf '%s\n' "$group" | grep -Eq "$allowed_group_pattern" || return 1
    path_mode_has_no_bits "$path" "$disallowed_mask"
}

audit_file_access_control() {
    local control_id="$1"
    local title="$2"
    local path="$3"
    local disallowed_mask="$4"
    local allowed_group_pattern="$5"
    local missing_ok="${6:-0}"
    local applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if file_access_ok "$path" "$disallowed_mask" "$allowed_group_pattern" "$missing_ok"; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

opasswd_access_ok() {
    file_access_ok "/etc/security/opasswd" "0177" "^(root)$" 1 \
        && file_access_ok "/etc/security/opasswd.old" "0177" "^(root)$" 1
}

local_filesystem_mounts_for_access_scan() {
    local exclude_fs="nfs|proc|cifs|smb|vfat|iso9660|efivarfs|selinuxfs|ncpfs"
    local exclude_paths="\/run|\/tmp|\/var\/tmp"

    findmnt -Dkerno fstype,target 2>/dev/null \
        | awk '($1 !~ /^\s*('"$exclude_fs"')/ && $2 !~ /^('"$exclude_paths"')(\/|$)/){print $2}'
}

world_writable_files_and_dirs_secured() {
    local mount_point
    local path
    local mode
    local sticky_mask="01000"

    while IFS= read -r mount_point; do
        while IFS= read -r -d $'\0' path; do
            [ -e "$path" ] || continue
            if [ -f "$path" ]; then
                return 1
            fi
            if [ -d "$path" ]; then
                mode="$(stat -Lc '%#a' "$path" 2>/dev/null)" || return 1
                [ $((mode & sticky_mask)) -gt 0 ] || return 1
            fi
        done < <(find "$mount_point" -mount -xdev \
            \( -path "*/containers/storage/*" -o -path "*/containerd/*" -o -path "*/kubelet/*" -o -path "/sys/*" -o -path "/snap/*" -o -path "/boot/efi/*" \) -prune \
            -o \( -type f -o -type d \) -perm -0002 -print0 2>/dev/null)
    done < <(local_filesystem_mounts_for_access_scan)
}

no_unowned_or_ungrouped_files_or_dirs() {
    local mount_point

    while IFS= read -r mount_point; do
        [ -z "$(find "$mount_point" -mount -xdev \
            \( -path "*/containers/storage/*" -o -path "*/containerd/*" -o -path "*/kubelet/*" -o -path "/sys/*" -o -path "/snap/*" -o -path "/boot/efi/*" \) -prune \
            -o \( -type f -o -type d \) \( -nouser -o -nogroup \) -print -quit 2>/dev/null)" ] || return 1
    done < <(local_filesystem_mounts_for_access_scan)
}

suid_sgid_files_found() {
    local mount_point

    while IFS= read -r mount_point; do
        [ -z "$(find "$mount_point" -xdev -type f \( -perm -2000 -o -perm -4000 \) -print -quit 2>/dev/null)" ] || return 0
    done < <(findmnt -Dkerno fstype,target,options 2>/dev/null \
        | awk '($1 !~ /^\s*(nfs|proc|smb|vfat|iso9660|efivarfs|selinuxfs)/ && $2 !~ /^\/run\/user\// && $3 !~ /noexec/ && $3 !~ /nosuid/) {print $2}')

    return 1
}

audit_7_1_1() {
    audit_file_access_control "7.1.1" "Ensure access to /etc/passwd is configured" "/etc/passwd" "0133" "^(root)$"
}

audit_7_1_2() {
    audit_file_access_control "7.1.2" "Ensure access to /etc/passwd- is configured" "/etc/passwd-" "0133" "^(root)$"
}

audit_7_1_3() {
    audit_file_access_control "7.1.3" "Ensure access to /etc/group is configured" "/etc/group" "0133" "^(root)$"
}

audit_7_1_4() {
    audit_file_access_control "7.1.4" "Ensure access to /etc/group- is configured" "/etc/group-" "0133" "^(root)$"
}

audit_7_1_5() {
    audit_file_access_control "7.1.5" "Ensure access to /etc/shadow is configured" "/etc/shadow" "0137" "^(root|shadow)$"
}

audit_7_1_6() {
    audit_file_access_control "7.1.6" "Ensure access to /etc/shadow- is configured" "/etc/shadow-" "0137" "^(root|shadow)$"
}

audit_7_1_7() {
    audit_file_access_control "7.1.7" "Ensure access to /etc/gshadow is configured" "/etc/gshadow" "0137" "^(root|shadow)$"
}

audit_7_1_8() {
    audit_file_access_control "7.1.8" "Ensure access to /etc/gshadow- is configured" "/etc/gshadow-" "0137" "^(root|shadow)$" 1
}

audit_7_1_9() {
    audit_file_access_control "7.1.9" "Ensure access to /etc/shells is configured" "/etc/shells" "0133" "^(root)$"
}

audit_7_1_10() {
    control_id="7.1.10"
    title="Ensure access to /etc/security/opasswd is configured"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if opasswd_access_ok; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_7_1_11() {
    control_id="7.1.11"
    title="Ensure world writable files and directories are secured"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if world_writable_files_and_dirs_secured; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_7_1_12() {
    control_id="7.1.12"
    title="Ensure no files or directories without an owner and a group exist"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if no_unowned_or_ungrouped_files_or_dirs; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_7_1_13() {
    control_id="7.1.13"
    title="Ensure SUID and SGID files are reviewed"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if suid_sgid_files_found; then
        manual_control "$control_id" "$title"
    else
        pass_control "$control_id" "$title"
    fi
}

passwd_uses_shadowed_passwords() {
    awk -F: 'BEGIN {bad=0} ($2 != "x") {bad=1} END {exit bad}' /etc/passwd 2>/dev/null
}

shadow_password_fields_not_empty() {
    awk -F: 'BEGIN {bad=0} ($2 == "") {bad=1} END {exit bad}' /etc/shadow 2>/dev/null
}

passwd_groups_exist() {
    awk -F: 'NR == FNR {group_gid[$3]=1; next} !($4 in group_gid) {bad=1} END {exit bad}' /etc/group /etc/passwd 2>/dev/null
}

shadow_group_empty() {
    local shadow_gid

    awk -F: 'BEGIN {bad=0} ($1 == "shadow" && $4 != "") {bad=1} END {exit bad}' /etc/group 2>/dev/null || return 1
    shadow_gid="$(getent group shadow 2>/dev/null | awk -F: '{print $3}')"
    [ -n "$shadow_gid" ] || return 0
    awk -F: -v gid="$shadow_gid" 'BEGIN {bad=0} ($4 == gid) {bad=1} END {exit bad}' /etc/passwd 2>/dev/null
}

no_duplicate_field_values() {
    local file="$1"
    local field="$2"

    [ -z "$(cut -d: -f "$field" "$file" 2>/dev/null | sort | uniq -d | head -n 1)" ]
}

local_interactive_user_homes() {
    local shell_regex

    shell_regex="$(valid_login_shells_regex)"
    [ -n "$shell_regex" ] || return 1
    awk -v pat="^(${shell_regex})$" -F: '$(NF) ~ pat {print $1 ":" $(NF-1)}' /etc/passwd 2>/dev/null
}

local_interactive_user_home_dirs_configured() {
    local user
    local home
    local owner

    while IFS=: read -r user home; do
        [ -n "$user" ] && [ -n "$home" ] || continue
        [ -d "$home" ] || return 1
        owner="$(stat -Lc '%U' "$home" 2>/dev/null)" || return 1
        [ "$owner" = "$user" ] || return 1
        path_mode_has_no_bits "$home" "027" || return 1
    done < <(local_interactive_user_homes)
}

dot_file_access_ok() {
    local dot_file="$1"
    local user="$2"
    local group="$3"
    local mask="$4"
    local owner
    local file_group

    owner="$(stat -Lc '%U' "$dot_file" 2>/dev/null)" || return 1
    file_group="$(stat -Lc '%G' "$dot_file" 2>/dev/null)" || return 1
    [ "$owner" = "$user" ] || return 1
    [ "$file_group" = "$group" ] || return 1
    path_mode_has_no_bits "$dot_file" "$mask"
}

local_interactive_user_dot_files_configured() {
    local user
    local home
    local group
    local dot_file
    local basename

    while IFS=: read -r user home; do
        [ -n "$user" ] && [ -n "$home" ] || continue
        [ -d "$home" ] || continue
        group="$(id -gn "$user" 2>/dev/null)" || return 1
        while IFS= read -r -d $'\0' dot_file; do
            basename="$(basename "$dot_file")"
            case "$basename" in
                .forward|.rhost)
                    return 1
                    ;;
                .netrc|.bash_history)
                    dot_file_access_ok "$dot_file" "$user" "$group" "0177" || return 1
                    ;;
                *)
                    dot_file_access_ok "$dot_file" "$user" "$group" "0133" || return 1
                    ;;
            esac
        done < <(find "$home" -xdev -type f -name '.*' -print0 2>/dev/null)
    done < <(local_interactive_user_homes)
}

audit_7_2_1() {
    control_id="7.2.1"
    title="Ensure accounts in /etc/passwd use shadowed passwords"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if passwd_uses_shadowed_passwords; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_7_2_2() {
    control_id="7.2.2"
    title="Ensure /etc/shadow password fields are not empty"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if shadow_password_fields_not_empty; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_7_2_3() {
    control_id="7.2.3"
    title="Ensure all groups in /etc/passwd exist in /etc/group"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if passwd_groups_exist; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_7_2_4() {
    control_id="7.2.4"
    title="Ensure shadow group is empty"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if shadow_group_empty; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_7_2_5() {
    control_id="7.2.5"
    title="Ensure no duplicate UIDs exist"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if no_duplicate_field_values "/etc/passwd" 3; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_7_2_6() {
    control_id="7.2.6"
    title="Ensure no duplicate GIDs exist"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if no_duplicate_field_values "/etc/group" 3; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_7_2_7() {
    control_id="7.2.7"
    title="Ensure no duplicate user names exist"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if no_duplicate_field_values "/etc/passwd" 1; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_7_2_8() {
    control_id="7.2.8"
    title="Ensure no duplicate group names exist"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if no_duplicate_field_values "/etc/group" 1; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_7_2_9() {
    control_id="7.2.9"
    title="Ensure local interactive user home directories are configured"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if local_interactive_user_home_dirs_configured; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

audit_7_2_10() {
    control_id="7.2.10"
    title="Ensure local interactive user dot files access is configured"
    applicability="l1-server,l1-workstation"

    should_run_control "$control_id" "$applicability" || return 0

    if local_interactive_user_dot_files_configured; then
        pass_control "$control_id" "$title"
    else
        fail_control "$control_id" "$title"
    fi
}

main() {
    print_banner
    parse_args "$@"
    setup_colors
    require_root

    audit_1_1_1_1
    audit_1_1_1_2
    audit_1_1_1_3
    audit_1_1_1_4
    audit_1_1_1_5
    audit_1_1_1_6
    audit_1_1_1_7
    audit_1_1_1_8
    audit_1_1_1_9
    audit_1_1_1_10
    audit_1_1_1_11
    audit_1_1_2_1_1
    audit_1_1_2_1_2
    audit_1_1_2_1_3
    audit_1_1_2_1_4
    audit_1_1_2_2_1
    audit_1_1_2_2_2
    audit_1_1_2_2_3
    audit_1_1_2_2_4
    audit_1_1_2_3_1
    audit_1_1_2_3_2
    audit_1_1_2_3_3
    audit_1_1_2_4_1
    audit_1_1_2_4_2
    audit_1_1_2_4_3
    audit_1_1_2_5_1
    audit_1_1_2_5_2
    audit_1_1_2_5_3
    audit_1_1_2_5_4
    audit_1_1_2_6_1
    audit_1_1_2_6_2
    audit_1_1_2_6_3
    audit_1_1_2_6_4
    audit_1_1_2_7_1
    audit_1_1_2_7_2
    audit_1_1_2_7_3
    audit_1_1_2_7_4
    audit_1_2_1_1
    audit_1_2_1_2
    audit_1_2_1_3
    audit_1_2_1_4
    audit_1_2_1_5
    audit_1_2_1_6
    audit_1_2_1_7
    audit_1_2_1_8
    audit_1_2_1_9
    audit_1_2_2_1
    audit_1_3_1_1
    audit_1_3_1_2
    audit_1_3_1_3
    audit_1_3_1_4
    audit_1_4_1
    audit_1_4_2
    audit_1_5_1
    audit_1_5_2
    audit_1_5_3
    audit_1_5_4
    audit_1_5_5
    audit_1_5_6
    audit_1_5_7
    audit_1_5_8
    audit_1_5_9
    audit_1_5_11
    audit_1_5_12
    audit_1_6_1
    audit_1_6_2
    audit_1_6_3
    audit_1_6_4
    audit_1_6_5
    audit_1_6_6
    audit_1_6_7
    audit_1_6_8
    audit_1_6_9
    audit_1_6_10
    audit_1_7_1
    audit_1_7_2
    audit_1_7_3
    audit_1_7_4
    audit_1_7_5
    audit_1_7_6
    audit_1_7_7
    audit_2_1_1
    audit_2_1_2
    audit_2_1_3
    audit_2_1_4
    audit_2_1_5
    audit_2_1_6
    audit_2_1_7
    audit_2_1_8
    audit_2_1_9
    audit_2_1_10
    audit_2_1_11
    audit_2_1_12
    audit_2_1_13
    audit_2_1_14
    audit_2_1_15
    audit_2_1_16
    audit_2_1_17
    audit_2_1_18
    audit_2_1_19
    audit_2_1_20
    audit_2_1_21
    audit_2_1_22
    audit_2_1_23
    audit_2_2_1
    audit_2_2_2
    audit_2_2_3
    audit_2_2_4
    audit_2_2_5
    audit_2_2_6
    audit_2_3_1_1
    audit_2_3_2_1
    audit_2_3_2_2
    audit_2_3_3_1
    audit_2_3_3_2
    audit_2_3_3_3
    audit_2_4_1_1
    audit_2_4_1_2
    audit_2_4_1_3
    audit_2_4_1_4
    audit_2_4_1_5
    audit_2_4_1_6
    audit_2_4_1_7
    audit_2_4_1_8
    audit_2_4_1_9
    audit_2_4_2_1
    audit_3_1_1
    audit_3_1_2
    audit_3_1_3
    audit_3_2_1
    audit_3_2_2
    audit_3_2_3
    audit_3_2_4
    audit_3_2_5
    audit_3_2_6
    audit_3_3_1_1
    audit_3_3_1_2
    audit_3_3_1_3
    audit_3_3_1_4
    audit_3_3_1_5
    audit_3_3_1_6
    audit_3_3_1_7
    audit_3_3_1_8
    audit_3_3_1_9
    audit_3_3_1_10
    audit_3_3_1_11
    audit_3_3_1_12
    audit_3_3_1_13
    audit_3_3_1_14
    audit_3_3_1_15
    audit_3_3_1_16
    audit_3_3_1_17
    audit_3_3_1_18
    audit_3_3_2_1
    audit_3_3_2_2
    audit_3_3_2_3
    audit_3_3_2_4
    audit_3_3_2_5
    audit_3_3_2_6
    audit_3_3_2_7
    audit_3_3_2_8
    audit_4_1_1
    audit_4_1_2
    audit_4_1_3
    audit_4_1_4
    audit_4_1_5
    audit_5_1_1
    audit_5_1_2
    audit_5_1_3
    audit_5_1_4
    audit_5_1_5
    audit_5_1_6
    audit_5_1_7
    audit_5_1_8
    audit_5_1_9
    audit_5_1_10
    audit_5_1_11
    audit_5_1_12
    audit_5_1_13
    audit_5_1_14
    audit_5_1_15
    audit_5_1_16
    audit_5_1_17
    audit_5_1_18
    audit_5_1_19
    audit_5_1_20
    audit_5_1_21
    audit_5_1_22
    audit_5_1_23
    audit_5_1_24
    audit_5_2_1
    audit_5_2_2
    audit_5_2_3
    audit_5_2_4
    audit_5_2_5
    audit_5_2_6
    audit_5_2_7
    audit_5_3_1_1
    audit_5_3_1_2
    audit_5_3_1_3
    audit_5_3_1_4
    audit_5_3_2_1
    audit_5_3_2_2
    audit_5_3_2_3
    audit_5_3_2_4
    audit_5_3_3_1_1
    audit_5_3_3_1_2
    audit_5_3_3_1_3
    audit_5_3_3_2_1
    audit_5_3_3_2_2
    audit_5_3_3_2_3
    audit_5_3_3_2_4
    audit_5_3_3_2_5
    audit_5_3_3_2_6
    audit_5_3_3_2_7
    audit_5_3_3_2_8
    audit_5_3_3_3_1
    audit_5_3_3_3_2
    audit_5_3_3_3_3
    audit_5_3_3_4_1
    audit_5_3_3_4_2
    audit_5_3_3_4_3
    audit_5_3_3_4_4
    audit_5_4_1_1
    audit_5_4_1_2
    audit_5_4_1_3
    audit_5_4_1_4
    audit_5_4_1_5
    audit_5_4_1_6
    audit_5_4_2_1
    audit_5_4_2_2
    audit_5_4_2_3
    audit_5_4_2_4
    audit_5_4_2_5
    audit_5_4_2_6
    audit_5_4_2_7
    audit_5_4_2_8
    audit_5_4_3_1
    audit_5_4_3_2
    audit_5_4_3_3
    audit_6_1_1_1_1
    audit_6_1_1_1_2
    audit_6_1_1_1_3
    audit_6_1_1_1_4
    audit_6_1_1_1_5
    audit_6_1_1_1_6
    audit_6_1_1_1_7
    audit_6_1_2_1
    audit_6_1_2_2
    audit_6_1_2_3
    audit_6_1_2_4
    audit_6_1_2_5
    audit_6_1_2_6
    audit_6_1_2_7
    audit_6_1_2_8
    audit_6_1_2_9
    audit_6_1_2_10
    audit_6_1_3_1
    audit_6_2_1_1
    audit_6_2_1_2
    audit_6_2_1_3
    audit_6_2_1_4
    audit_6_2_2_1
    audit_6_2_2_2
    audit_6_2_2_3
    audit_6_2_2_4
    audit_6_2_3_1
    audit_6_2_3_2
    audit_6_2_3_3
    audit_6_2_3_4
    audit_6_2_3_5
    audit_6_2_3_6
    audit_6_2_3_7
    audit_6_2_3_8
    audit_6_2_3_9
    audit_6_2_3_10
    audit_6_2_3_11
    audit_6_2_3_12
    audit_6_2_3_13
    audit_6_2_3_14
    audit_6_2_3_15
    audit_6_2_3_16
    audit_6_2_3_17
    audit_6_2_3_18
    audit_6_2_3_19
    audit_6_2_3_20
    audit_6_2_3_21
    audit_6_2_3_22
    audit_6_2_3_23
    audit_6_2_3_24
    audit_6_2_3_25
    audit_6_2_3_26
    audit_6_2_3_27
    audit_6_2_3_28
    audit_6_2_3_29
    audit_6_2_3_30
    audit_6_2_4_1
    audit_6_2_4_2
    audit_6_2_4_3
    audit_6_2_4_4
    audit_6_2_4_5
    audit_6_2_4_6
    audit_6_2_4_7
    audit_6_2_4_8
    audit_6_2_4_9
    audit_6_2_4_10
    audit_6_3_1
    audit_6_3_2
    audit_6_3_3
    audit_7_1_1
    audit_7_1_2
    audit_7_1_3
    audit_7_1_4
    audit_7_1_5
    audit_7_1_6
    audit_7_1_7
    audit_7_1_8
    audit_7_1_9
    audit_7_1_10
    audit_7_1_11
    audit_7_1_12
    audit_7_1_13
    audit_7_2_1
    audit_7_2_2
    audit_7_2_3
    audit_7_2_4
    audit_7_2_5
    audit_7_2_6
    audit_7_2_7
    audit_7_2_8
    audit_7_2_9
    audit_7_2_10

    print_summary
    [ "$FAIL_COUNT" -eq 0 ]
}

main "$@"
