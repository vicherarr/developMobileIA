#!/usr/bin/env bash
# setup_host.sh - fix and verify the *host* prerequisites this agent cannot touch
# from its sandbox: KVM access, an AVD, a Gradle-compatible JDK, a writable SDK.
#
# Run this in your own terminal (not through the agent), from the kit root:
#
#   ./scripts/setup_host.sh            # diagnose + run safe fixes, then doctor
#   ./scripts/setup_host.sh --dry-run  # only report what would change
#
# Options:
#   --avd <name>     AVD name to create (default: medium_phone)
#   --profile <p>    Device profile for the AVD (default: medium_phone)
#   --jdk <path>     Use this JDK instead of auto-detection
#   --skip-avd       Do not create an AVD
#   --yes            Do not ask for confirmation before sudo commands
#   --dry-run        Report only, change nothing
#   -h, --help       Show this help
#
# It never edits the Android project. Steps that need root print the exact
# command first; with --yes they are executed through sudo.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=/dev/null
. "${PIPELINE_ROOT}/scripts/lib/android_env.sh"

AVD_NAME="medium_phone"
PROFILE="medium_phone"
JDK_OVERRIDE=""
DO_AVD=1
ASSUME_YES=0
DRY_RUN=0

usage() { sed -n '2,24p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --avd)      AVD_NAME="${2:-}"; shift 2 ;;
    --profile)  PROFILE="${2:-}"; shift 2 ;;
    --jdk)      JDK_OVERRIDE="${2:-}"; shift 2 ;;
    --skip-avd) DO_AVD=0; shift ;;
    --yes|-y)   ASSUME_YES=1; shift ;;
    --dry-run)  DRY_RUN=1; shift ;;
    -h|--help)  usage; exit 0 ;;
    *)          usage >&2; printf 'unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done

ISSUES=0
note() { printf '\n%s== %s ==%s\n' "${__C_BLU}" "$*" "${__C_RESET}"; }
done_ok() { ok "$*"; }
todo() { ISSUES=$((ISSUES + 1)); warn "$*"; }

run_root() {
  local desc="$1"; shift
  printf '  sudo %s\n' "$*"
  if [ "$DRY_RUN" -eq 1 ]; then return 1; fi
  if [ "$ASSUME_YES" -eq 0 ]; then
    printf '  run it now? [y/N] '
    local a; read -r a
    case "$a" in y|Y) ;; *) warn "skipped: ${desc}"; return 1 ;; esac
  fi
  sudo "$@"
}

# ---------------------------------------------------------------------------
note "1/4 JDK (Gradle and AGP need 17+)"
# ---------------------------------------------------------------------------
jdk_major() { "$1/bin/java" -version 2>&1 | head -1 | sed 's/.*version "\([0-9]*\).*/\1/'; }

if [ -n "$JDK_OVERRIDE" ]; then
  CANDIDATES=("$JDK_OVERRIDE")
else
  CANDIDATES=()
  for c in "${JAVA_HOME:-}" /usr/lib/jvm/* "$HOME"/.local/share/mise/installs/java/* \
           /opt/android-studio/jbr "$HOME"/.local/share/JetBrains/Toolbox/apps/android-studio/jbr; do
    [ -n "$c" ] && [ -x "$c/bin/java" ] && CANDIDATES+=("$c")
  done
fi

BEST_JDK=""; BEST_MAJOR=0
SEEN=" "
for c in "${CANDIDATES[@]}"; do
  real="$(readlink -f "$c")"
  case "$SEEN" in *" $real "*) continue ;; esac
  SEEN="${SEEN}${real} "
  m="$(jdk_major "$c" || true)"
  [ -n "$m" ] || continue
  printf '  found JDK %-3s %s\n' "$m" "$c"
  # Prefer 17/21 (validated with AGP 9), then any 17..25.
  if [ "$m" -ge 17 ] 2>/dev/null && [ "$m" -le 25 ] 2>/dev/null; then
    if [ "$m" -eq 21 ] || [ "$m" -eq 17 ]; then
      BEST_JDK="$c"; BEST_MAJOR="$m"; break
    elif [ "$BEST_MAJOR" -eq 0 ]; then
      BEST_JDK="$c"; BEST_MAJOR="$m"
    fi
  fi
done

if [ -n "$BEST_JDK" ]; then
  done_ok "use JAVA_HOME=${BEST_JDK} (JDK ${BEST_MAJOR})"
  printf '  export JAVA_HOME="%s"\n' "$BEST_JDK"
  if [ "$BEST_MAJOR" -gt 21 ]; then
    done_ok "JDK ${BEST_MAJOR} is newer than AGP 9's tested baseline (17-21), but Gradle 9.1 supports it and the pipeline template builds on JDK 25 (verified)."
  fi
else
  todo "no JDK 17-25 found"
  if command -v pacman >/dev/null 2>&1; then
    printf '  install one:  sudo pacman -S jdk21-openjdk\n'
    printf '  then:         export JAVA_HOME=/usr/lib/jvm/java-21-openjdk\n'
    if run_root "install jdk21-openjdk" pacman -S --needed --noconfirm jdk21-openjdk; then
      done_ok "installed jdk21-openjdk"
    fi
  elif command -v mise >/dev/null 2>&1; then
    printf '  install one:  mise use -g java@21\n'
  fi
fi

# ---------------------------------------------------------------------------
note "2/4 KVM (hardware acceleration for the emulator)"
# ---------------------------------------------------------------------------
if [ -e /dev/kvm ]; then
  if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    done_ok "/dev/kvm present and accessible"
  else
    todo "/dev/kvm exists but this user cannot use it"
    printf '  fix:  sudo usermod -aG kvm "$USER"   # then log out and back in\n'
    run_root "add user to kvm group" usermod -aG kvm "$USER" || true
  fi
elif grep -q kvm /proc/misc 2>/dev/null; then
  todo "/dev/kvm missing although the kernel has kvm (/proc/misc)"
  printf '  the device node was not created (udev/container). Fix:\n'
  printf '    sudo modprobe kvm_intel kvm_amd 2>/dev/null || true\n'
  printf '    sudo mknod /dev/kvm c 10 232\n'
  printf '    sudo chown root:kvm /dev/kvm && sudo chmod 660 /dev/kvm\n'
  printf '    sudo groupadd -f kvm && sudo usermod -aG kvm "$USER"\n'
  if run_root "create /dev/kvm" bash -c '
      modprobe kvm_intel 2>/dev/null || modprobe kvm_amd 2>/dev/null || true
      [ -e /dev/kvm ] || mknod /dev/kvm c 10 232
      chown root:kvm /dev/kvm; chmod 660 /dev/kvm
      groupadd -f kvm; usermod -aG kvm "$SUDO_USER"
    '; then
    done_ok "/dev/kvm created (re-login for the group change)"
  fi
else
  todo "/dev/kvm unavailable: virtualization is off in firmware or the kernel lacks kvm"
  printf '  enable VT-x/AMD-V in the BIOS/UEFI, then reboot and re-run this script.\n'
  printf '  meanwhile: use a physical device (USB debugging) for G6.\n'
fi

# ---------------------------------------------------------------------------
note "3/4 Android SDK (writable + system image)"
# ---------------------------------------------------------------------------
if [ -n "${ANDROID_SDK:-}" ]; then
  if [ -w "${ANDROID_SDK}" ]; then
    done_ok "SDK writable: ${ANDROID_SDK}"
  else
    todo "SDK is not writable: ${ANDROID_SDK}"
    printf '  fix:  sudo chown -R "$USER":"$USER" "%s"\n' "$ANDROID_SDK"
    run_root "chown the SDK" chown -R "${USER}:${USER}" "${ANDROID_SDK}" || true
  fi
  if [ -n "$(ls -1 "${ANDROID_SDK}/system-images" 2>/dev/null)" ]; then
    done_ok "system images: $(ls -1 "${ANDROID_SDK}/system-images" | tr '\n' ' ')"
  else
    todo "no system images installed"
    printf '  fix:  android sdk install "system-images;android-36;google_apis;x86_64"\n'
  fi
else
  todo "Android SDK not found (set ANDROID_HOME)"
fi

# ---------------------------------------------------------------------------
note "4/4 AVD (emulator)"
# ---------------------------------------------------------------------------
if [ "$DO_AVD" -eq 1 ]; then
  AVDS="$(android_cli emulator list 2>/dev/null | sed 's/^[* ]*//' || true)"
  if [ -n "$AVDS" ]; then
    done_ok "AVDs: $(printf '%s' "$AVDS" | tr '\n' ' ')"
  elif [ "$DRY_RUN" -eq 1 ]; then
    printf '  DRY-RUN: android emulator create %s\n' "$PROFILE"
  else
    log "no AVD found; creating '${PROFILE}'"
    if android_cli emulator create "$PROFILE"; then
      done_ok "created AVD from profile '${PROFILE}'"
    else
      todo "could not create an AVD (missing system image? see step 3)"
    fi
  fi
else
  printf '  skipped (--skip-avd)\n'
fi

# ---------------------------------------------------------------------------
printf '\n'
if [ "$ISSUES" -eq 0 ]; then
  ok "host looks ready"
else
  warn "${ISSUES} item(s) need attention (see the commands above)"
fi

if [ "$DRY_RUN" -eq 0 ]; then
  printf '\nRe-run the doctor for the full picture:\n  %s/scripts/doctor.sh\n\n' "$PIPELINE_ROOT"
fi
exit 0
