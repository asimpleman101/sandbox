#!/bin/bash
set -o pipefail
red='\e[1;91m'
grn='\e[1;92m'
cyn='\e[1;96m'
rst='\e[0m'
t=$(nproc --all)
if [[ "${BASH_SOURCE[0]}" != "$(basename -- "$0")" ]]; then
    echo -e "\n${red}Do not source this script!\n\nUsage:${rst} sudo bash $(basename -- "$0")\n"
    kill -INT $$
fi
if [ "$EUID" -ne 0 ]; then
    echo -e "\n${red}Must run this script with root!${rst}\n"
    exit 1
fi
echo ""
read -p "Enter user name: " USER
HOME=/home/"$USER"
tmp="$HOME"/.tmp
projects_dir="$HOME"/android
mkdir -p "$tmp"
mkdir -p "$projects_dir"
runas () { sudo -u "$USER" "$@" ; }
die () { echo -e "\n${red}:: $1 ${rst}  $?\n" ; }
msg () { echo -e "\n${grn}:: $1${rst}\n" ; }
if [ -f "$tmp/count1" ]; then
    msg "Setup already ran before."
    msg "You may need to run some commands manually"
    msg "if the script did not succeed."
    sleep 1
fi
cd "$HOME" || exit 1
msg "Arch Linux Arm setup begins"
sleep 1
if [ ! -f "$tmp/count1" ]; then
    msg "Checking prerequisites..."
    pkgs="autoconf autoconf-archive automake axel binutils bison ccache clang curl fakeroot file findutils flex gawk gcc gettext git go grep groff gzip hub jq libtool lzip m4 make pacman patch patchelf pkgconf python sed subversion svn texinfo unzip wget which"
    if [ -f "$tmp/count1" ]; then
        for pkg in $pkgs; do
            pacman -Qi "${pkg}" &>/dev/null || {
                msg "Installing ${cyn}${pkg}${rst}"
                yes ""|pacman -S "${pkg}"
            }
        done
    else
        pacman -S - < $(echo $pkgs)
    fi
    msg "Packages up-to-date."
	touch "$tmp/count1"
fi
if [ ! -f "$tmp/count2" ]; then
    cd "$tmp" || exit 1 
    msg "Making fakeroot package..."
    wget 'http://ftp.debian.org/debian/pool/main/f/fakeroot/fakeroot_1.24.orig.tar.gz'
    tar xvf fakeroot_1.24.orig.tar.gz
    cd "$tmp/fakeroot-1.24/" || exit 1
    ./bootstrap
    ./configure --prefix=/usr \
        --libdir=/opt/fakeroot/libs \
        --disable-static \
        --with-ipc=tcp
    make -j$(nproc --all) 
    msg "Fakeroot package ready. Installing..." 
    sudo make install
    msg "Fakeroot installed."
    touch "$tmp/count2"
fi
if [ ! -f "$tmp/count3" ]; then
    cd "$tmp" || exit 1
    msg "Modifying makepkg..."
    if [ ! -d "$tmp/update-makepkg" ]; then
        wget --no-check-certificate 'https://docs.google.com/uc?export=download&id=1-toECHlCTeVdEJ77C8yhBhfmVBsQYAVz' -O "$tmp"/update-makepkg.zip &>/dev/null
        unzip "$tmp/update-makepkg.zip" -d "$tmp/update-makepkg" &>/dev/null
    fi
    cp /usr/bin/makepkg /usr/bin/makepkg.bk || {
        die "Failed to backup makepkg. Aborting."
        exit 1
    }
    cp -f "$tmp/update-makepkg/makepkg" /usr/bin/makepkg
    chmod +x /usr/bin/makepkg
    msg "Makepkg ready."
    cd "$HOME" || exit 1
	touch "$tmp/count3"
fi
if [ ! -f "$tmp/count4" ]; then
    cd "$tmp" || exit 1
    echo ""
    msg "Installing yay to build needed packages..."
    git clone https://aur.archlinux.org/yay.git
    cd yay || die "Yay failed to clone!"
    yes ""|makepkg -si
    msg "Yay installed."
    cd "$HOME" || exit 1
    touch "$tmp"/count4
fi
if [ ! -f "$tmp/count5" ]; then  
    msg "Checking for user-package list..."
    if [ ! -f "$HOME/pkglist.txt" ]; then
        wget --no-check-certificate 'https://docs.google.com/uc?export=download&id=100coVxu7zDBlmpbmsbY_tQBybTWgouPA' -O "$HOME"/pkglist.txt &>/dev/null
    fi
    if [ -f "$HOME/pkglist.txt" ]; then
        msg "Installing user packages from provided list..."
        if [ -f "$tmp/count5" ]; then
            cat "$HOME/pkglist.txt" | while read pkg || [[ -n $pkg ]]; do
            yay -Qi "${pkg}" &>/dev/null || {
                msg "Installing ${cyn}${pkg}${rst}"
                yes ""|runas yay -S "${pkg}"
            }
            done
        else
            pacman -S - < "$HOME"/pkglist.txt
        fi
        msg "User packages installed."
    fi
    touch "$tmp/count5"
fi
msg "Setup Complete!"
cd "$HOME" || exit 1
read -rp $'\e[1;92m:: Do you want to sync a project?\e[0m ' ifsync
if [[ "${ifsync,,}" =~ ^(y|yes)$ ]]; then
    until [[ "${dosync,,}" =~ ^(n|no)$ ]]; do
        until [[ "${yn,,}" =~ ^(y|yes)$ ]]; do
            cd $projects_dir || exit 1
            manifest=
            read -rp $'\e[1;92m:: Username/Repo:\e[0m ' url
            read -rp $'\e[1;92m:: Repo Branch:\e[0m ' branch
            read -rp $'\e[1;92m:: Project Folder:\e[0m ' folder
            msg "If no manifest, hit ${cyn}ENTER${rst}"
            read -rp $'\e[1;92m:: Local Manifest [User/Repo]:\e[0m ' manifest
            read -rp $'\e[1;92m:: Shallow Clone?\e[0m ' shallow
            echo ""
            read -rp $'\e[1;92m:: Is this correct?\e[0m ' yn
        done
        mkdir "$folder" && cd "$folder" || exit 1
        if [[ "${shallow,,}" =~ ^(y|yes)$ ]]; then
            runas repo init -u git://github.com/"$url" -b "$branch" --depth=1 --groups=all,-notdefault,-device,-darwin,-x86,-mips,-exynos5,mako || {
                die "Init failed!"
                exit 1
            }
        else
            runas repo init -u git://github.com/"$url" -b "$branch" || {
                die "Init failed!"
                exit 1
            }
        fi
        if [[ $manifest != "" ]]; then runas git clone https://github.com/"$manifest" .repo/local_manifests; fi
        runas repo sync -j"$t" -cq --optimized-fetch --no-clone-bundle --no-tags || {
            die "Sync aborted!"
            exit 1
        }
        read -rp $'\e[1;92m:: Do you want to sync another project?\e[0m ' dosync
    done
fi
read -rp $'\e[1;92m:: Do you want to clone a repo?\e[0m ' ifclone
if [[ "${ifclone,,}" =~ ^(y|yes)$ ]]; then
    until [[ "${doclone,,}" =~ ^(n|no)$ ]]; do
        cd $projects_dir || exit 1
        until [[ "${yn,,}" =~ ^(y|yes)$ ]]; do
            read -rp $'\e[1;92m:: Username/Repo:\e[0m ' url
            read -rp $'\e[1;92m:: Repo branch:\e[0m ' branch
            read -rp $'\e[1;92m:: Project Folder:\e[0m ' folder
            msg "If no submodules, hit ${cyn}ENTER${rst}"
            read -rp $'\e[1;92m:: Clone submodules?\e[0m ' subs
            read -rp $'\e[1;92m:: Is this correct?\e[0m ' yn
        done
        if [[ "${subs,,}" =~ ^(y|yes)$ ]]; then
            runas git clone --recurse-submodules -j"$t" -b "$branch" https://github.com/"$url" $projects_dir/"$folder"
        else
            runas git clone -j"$t" -b "$branch" https://github.com/"$url" $projects_dir/"$folder"
        fi
        read -rp $'\e[1;92m:: Do you want to clone another repo?\e[0m ' doclone
    done
fi
msg "Enjoy!"
rm -rf "$tmp"