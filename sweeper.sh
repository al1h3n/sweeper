#!/usr/bin/env bash
# MM    MM              dd           bb                         lll  1  hh      333333
# MMM  MMM   aa aa      dd   eee     bb      yy   yy      aa aa lll 111 hh         3333 nn nnn
# MM MM MM  aa aaa  dddddd ee   e    bbbbbb  yy   yy     aa aaa lll  11 hhhhhh    3333  nnn  nn
# MM    MM aa  aaa dd   dd eeeee     bb   bb  yyyyyy    aa  aaa lll  11 hh   hh     333 nn   nn
# MM    MM  aaa aa  dddddd  eeeee    bbbbbb       yy     aaa aa lll 111 hh   hh 333333  nn   nn
#                                             yyyyy
# Support - al1h3n(tg,ds) | Donate me - paypal.me/al1h3n
# Part of the Cleanus Pack.
# ==============================================================================

# Colors, but only when stdout is a terminal. Under systemd, cron or a pipe the
# escape codes would end up as literal garbage in the log.
# shellcheck disable=SC2034 # BLUE is unused here, kept for user tweaks
if [ -t 1 ];then
	GREEN="\e[32m"
	YELLOW="\e[33m"
	RED="\e[31m"
	BLUE="\e[34m"
	RESET="\e[0m"
	PINK="\033[38;5;213m"
	PURPLE="\033[38;5;171m"
	VIOLET="\033[38;5;141m"
	YELLOW2="\033[38;5;226m"
	CYAN="\033[38;5;37m"
	AZURE="\033[38;5;33m"
	ROSE="\033[38;5;197m"
	LIME="\033[38;5;46m"
	echo -e "\033]0;Sweeper v1 - al1h3n | PART of Cleanus Pack v1\007"
else
	GREEN=""; YELLOW=""; RED=""; BLUE=""; RESET=""
	PINK=""; PURPLE=""; VIOLET=""; YELLOW2=""
	CYAN=""; AZURE=""; ROSE=""; LIME=""
fi

# If script is not run as root, restart it as root automatically.
if [ "$EUID" -ne 0 ];then
	echo -e "${YELLOW}Elevation needed. Restarting with sudo..${RESET}"
	exec sudo "${BASH:-bash}" "$0" "$@"
fi

exists(){
	command -v "$1" >/dev/null 2>&1
}

# True when we can prompt a human. Interactive package managers are skipped
# otherwise, so the script never hangs in a systemd unit or a cron job.
interactive(){
	[ -t 0 ]
}

# Human readable size of a path. Prints 0 when the path is missing.
size_of(){
	[ -e "$1" ] || { echo 0; return 0; }
	du -sh "$1" 2>/dev/null | cut -f1
}

# Empty a log file, but only if it already exists. Plain `truncate` would
# create the file, which fabricates logs on distros that never had them.
truncate_log(){
	[ -f "$1" ] && truncate -s 0 "$1"
	return 0
}

# Warn once about a tool we wanted but do not have, instead of dying.
missing(){
	echo -e "${RED} -> $1 not found, skipping.${RESET}"
}

echo -e "${PINK}Sweeper by${RESET} ${PURPLE}al1h3n${RESET} | ${VIOLET}PART${RESET} of ${YELLOW2}Cleanus Pack${RESET}"
echo -e "${GREEN}=========================================="
echo -e "    STARTING SYSTEM MAINTENANCE TASK      "
echo -e "==========================================${RESET}"

echo -e "\n${CYAN}[1/2] Cleaning kernel (trash, logs, tmp, swap)...${RESET}"

echo " -> Rebuilding font cache..."
if exists fc-cache;then fc-cache -rv;else missing fc-cache;fi

echo " -> Cleaning temporary files..."
# Whitelist the sockets and lock directories a running desktop still needs.
# A blind `rm -rf /tmp/*` kills X11, Wayland and systemd unit private dirs.
find /tmp -mindepth 1 -maxdepth 1 \
	! -name '.X11-unix' \
	! -name '.ICE-unix' \
	! -name '.XIM-unix' \
	! -name '.font-unix' \
	! -name '.Test-unix' \
	! -name 'systemd-private-*' \
	-exec rm -rf {} + 2>/dev/null

echo " -> Cleaning logs..."
# find instead of /var/log/**/*.gz: `**` only recurses when globstar is on,
# so the old glob silently skipped every nested log directory.
find /var/log -type f \( -name '*.gz' -o -name '*.1' \) -delete 2>/dev/null
if exists journalctl;then journalctl --vacuum-time=1d;fi
truncate_log /var/log/alternatives.log
truncate_log /var/log/syslog

for user_dir in /home/*;do
	[ -d "$user_dir" ] || continue
	user_name=$(basename "$user_dir")
	echo -e " -> Cleaning trash & cache for ${ROSE}${user_name}${RESET}"
	cache_size=$(size_of "$user_dir/.cache")
	trash_size=$(size_of "$user_dir/.local/share/Trash")
	rm -rf "${user_dir:?}/.cache/"* 2>/dev/null
	rm -rf "${user_dir:?}/.local/share/Trash/"* 2>/dev/null
	echo -e "${GREEN}    freed ~${cache_size} of cache, ~${trash_size} of trash${RESET}"
done

echo " -> Dropping caches and cycling swap..."
sync
# 3 is the best.
echo 3 >/proc/sys/vm/drop_caches 2>/dev/null||echo -e "${YELLOW} -> Could not drop caches (read-only /proc?).${RESET}"
# Only works if you have enough RAM to hold current swap data.
if exists swapoff && swapoff -a;then
	swapon -a
else
	echo -e "${YELLOW} -> Swap not cycled (not enough free RAM?).${RESET}"
fi

echo -e "\n${AZURE}[2/2] Cleaning package managers...${RESET}"

if exists pct;then # Proxmox.
truncate_log /var/log/pve/tasks/index
fi

if exists pacman;then # Arch, Endeavour, Cachy, Manjaro etc.
pacman -Syu --noconfirm
mapfile -t orphans < <(pacman -Qdttq || true)
[ ${#orphans[@]} -gt 0 ]&&pacman -Runs "${orphans[@]}" --noconfirm
mapfile -t deps < <(pacman -Qqd || true)
[ ${#deps[@]} -gt 0 ]&&pacman -Rsu "${deps[@]}" --noconfirm
pacman -Scc --noconfirm
fi

if exists paccache;then # Arch.
before=$(size_of /var/cache/pacman/pkg)
paccache -ruk0;paccache -rk1
echo -e "${GREEN}Cache went from ~${before} to ~$(size_of /var/cache/pacman/pkg)${RESET}"
# Delete removed packages from disk, keep 2 recent versions.
fi

if exists apt;then # Debian, Ubuntu, Mint, ELementaryOS, Kali, Proxmox. Includes dpkg as well.
export DEBIAN_FRONTEND=noninteractive
apt update;apt full-upgrade -y;apt autoremove -y;apt clean;apt autoclean
elif exists apt-get;then # Older manager of Debian family. Skipped when apt already ran.
export DEBIAN_FRONTEND=noninteractive
apt-get update;apt-get full-upgrade -y;apt-get autoremove -y;apt-get clean
fi

if exists dnf;then # Fedora, RedHat.
dnf upgrade --refresh -y
dnf clean all;dnf autoremove -y
# -y on the remove too, otherwise it blocks forever waiting for a keypress.
mapfile -t extras < <(dnf repoquery --extras --qf '%{name}\n' || true)
[ ${#extras[@]} -gt 0 ]&&dnf remove -y "${extras[@]}"
if exists package-cleanup;then package-cleanup --orphans --leaves --cleandupes --noprompt;fi
fi

if exists apk;then # Alpine.
apk update;apk upgrade
apk cache clean
fi

if exists pkg_add;then # OpenBSD.
pkg_add -I -Uu;syspatch;fw_update
pkg_delete -I -a
rcctl restart unwind;arp -da
fi

if exists zypper;then # OpenSUSE.
zypper refresh;zypper --non-interactive dist-upgrade
zypper clean --all
fi

if exists emerge;then # Gentoo.
if interactive;then
emerge -a --sync;emerge -avuDN @world;emerge -a --depclean
else
emerge --sync;emerge -uDN --quiet @world;emerge --depclean --quiet
fi
if exists eclean-dist;then eclean-dist -d;eclean-pkg;fi
fi

if exists xbps-install;then # Void Linux.
xbps-install -Syu;xbps-remove -Ooy;vkpurge rm all
fi

if exists eopkg;then # Solis.
eopkg ur -y;eopkg upgrade -y;eopkg rmo;eopkg dc
fi

if exists slackpkg;then # Slackware.
yes|slackpkg update;yes|slackpkg upgrade-all;yes|slackpkg clean-system
fi

if exists flatpak;then # Additional PMs.
flatpak update -y;flatpak uninstall -y --unused
fi

if exists snap;then # Ubuntu.
yes|snap refresh;rm -rf /var/lib/snapd/cache/*
fi

if exists brew;then # macOS.
brew update;brew upgrade;brew upgrade --cask
brew autoremove;brew cleanup --prune=all
fi

if exists yay;then # Arch - AUR.
yay -Syu --noconfirm
mapfile -t orphans < <(yay -Qdtq || true)
[ ${#orphans[@]} -gt 0 ]&&yay -Runs "${orphans[@]}" --noconfirm
yay -Scc --noconfirm
fi

if exists paru;then # Arch - AUR.
paru -Syu --noconfirm
mapfile -t orphans < <(paru -Qdtq || true)
[ ${#orphans[@]} -gt 0 ]&&paru -Runs "${orphans[@]}" --noconfirm
paru -Scc --noconfirm
fi

# NixOS manages garbage collection declaratively (nix.gc.automatic), and
# `-d` there deletes the generations you roll back to, so leave it alone.
if exists nix-collect-garbage && [ ! -e /etc/NIXOS ];then # any OS with nix installed.
nix-collect-garbage -d
fi

# Enable to delete old generations.
# if exists nix-collect-garbage;then
# nix-collect-garbage -d
# fi

echo -e "\n${LIME}==========================================${RESET}"
echo -e "${LIME}      SYSTEM CLEANING COMPLETE!           ${RESET}"
echo -e "${LIME}==========================================${RESET}"

exit 0
