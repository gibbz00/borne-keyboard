#!/bin/sh

# Asumes that system is running on Evolve Arch Linux 

# Requires: yay aur helper
# Uses environment variable SSHPASS for non-interactive ssh password logins
# 	must be set before running script
# 	See man 1 sshpass for more info
# Concept:
# Setup build environment if needed
# Builds files runnig x86_64 machine 
# rsyncs builds files over to pi
# pi flashes boards

set -e

test -n "$SSHPASS" || (echo "SHHPASS must be exported to run this script"; exit 1)

REMOTE_USER_NAME="gibbz"
REMOTE_HOST_NAME="evolve-rpi4.lan"
BUILDS_DIRECTORY="$(pwd)/builds"
mkdir --verbose --parent "$BUILDS_DIRECTORY"

# check dependencies
# https://github.com/Jguer/yay/issues/1552
# --needed flag does not really work with AUR packages
# hence all the extra flags
YAY_FLAGS='--needed --noconfirm --norebuild --noredownload --nocleanmenu --nodiffmenu --noremovemake'
# yay -S $YAY_FLAGS  zephyr-sdk python-jsonschema remarshal arm-none-eabi-gcc 
# zephyr-sdk, remarshal, openocd-git are still not being caught as downloaded, uncommenting them for now

setup_build_environment() {
	# forced to use -e flags since -d does not count hidden directories as "directories"
	if ! ( test -e zmk/.git && test -e Adafruit_nRF52_Bootloader/.git )
	then
		git submodule update --init
		(
			cd Adafruit_nRF52_Bootloader
			# Until keyboard is merged uppstream
			git remote add borne https://github.com/gibbz00/Adafruit_nRF52_Bootloader
		)
		cd zmk
		# Until keyboard is merged uppstream
		git remote add borne https://github.com/gibbz00/zmk

		# Zephyr development setup
		ZEPHYRRC="$HOME/.config/bash/bash.d/zephyr.bash"
		test -f "$ZEPHYRRC" || cp /usr/share/zephyr-sdk/zephyrrc "$ZEPHYRRC"; chmod +x "$ZEPHYRRC"

		# ZMK repo setup
		west init -l app/
		west update
		west zephyr-export
	fi
	(
		cd Adafruit_nRF52_Bootloader
		git pull borne master
	)
	(
		cd zmk
		git pull borne master
	)
}
 
bootloader_build() {(
    cd Adafruit_nRF52_Bootloader/
    KEYBOARD="borne_keyboard"
    make BOARD="$KEYBOARD" all
    # Extract the correct hex file
    cp _build/build-"$KEYBOARD"/*s140*.hex "$BUILDS_DIRECTORY/"
	# tell openocd which file to use, prepends BOOTLOADER file 
	echo -e "set BOOTLOADER $(ls builds/*s140*.hex)\n $(cat openocd/flash.cfg)" > openocd/flash.cfg

)}

# Build the applications for the respective halves
zmk_build() {(
    cd zmk/app
    for side in left right
    do
        west build -d build/$side --pristine --board borne -- -DSHIELD=borne_$side
        cp build/$side/zephyr/zmk.uf2 "$BUILDS_DIRECTORY"/zmk-$side.uf2
    done
)}

rsync_flash_files() {
	# rsync required on remote raspberry too
	sshpass -e ssh -o StrictHostKeyChecking=no "$REMOTE_USER_NAME@$REMOTE_HOST_NAME" "yay -S --needed rsync"

	rsync -r --rsh="sshpass -e ssh -o StrictHostKeyChecking=no" "$BUILDS_DIRECTORY" "$REMOTE_USER_NAME@$REMOTE_HOST_NAME":/home/"$REMOTE_USER_NAME"/borne-keyboard/
	# openocd scripts and configs
	rsync -r --rsh="sshpass -e ssh -o StrictHostKeyChecking=no" "openocd" "$REMOTE_USER_NAME@$REMOTE_HOST_NAME":/home/"$REMOTE_USER_NAME"/borne-keyboard/
}


## Flash bootloader ##
# Ran in remote rpi aarch64 environment"
rpi_flash() {
	set -e 
	# see YAY_FLAGS definition for as to why this is commented out
    # yay -S $YAY_FLAGS  openocd-git
    # PKGBUILD seems to include rasbperry pi gpio support out of the box (bcm2835gpio)
	cd "borne-keyboard"
	# HACK: remote user name has to be defined twice
	REMOTE_USER_NAME="gibbz"

	cd openocd
    LOGPATH="openocd-check-health.log"
    # Check health
    sudo sh -c "openocd -f openocd.cfg -f check-health.cfg 2>&1 | tee "$LOGPATH""
    # Check if nrf was halted (thus found)
    if ! grep --quiet --fixed-strings "halted" "$LOGPATH"
    then
        echo "
            Errors encountered when during pre-flash openocd check.
            Check $LOGPATH for more info.
            Aborting...
        "
        exit 1
    else
		# Not really working since $ targets isn't writing much to stdout compared to when it's used of telnet
		# All chips I got where unlocked, skipping this part for now. 
        # Check if it needs to be unlocked
        # 	if ! grep --quiet --fixed-strings "0x00000001" "$LOGPATH"
        # 	then
        # 	    echo "Unlocking the nrf52840..."
		# 		sudo sh -c "openocd -f openocd.cfg -f unlock.cfg"
        # 	fi

        # Flash bootloader and save device name for uf2 application flashing
        (sudo dmesg --notime --follow-new) > /tmp/dmesg.log &
		sudo sh -c "openocd -f openocd.cfg -f flash.cfg"
        pkill --newest dmesg
        device=$(
            grep "Attached SCSI removable disk" /tmp/dmesg.log | \
            grep --only-matching --perl-regexp "(?<=\[)[[:alnum:]]*(?=\])" 
        )
        rm /tmp/dmesg.log

        if test -z "$device"
        then
            echo "UF2 boot device not found. Aborting..."
            exit 1
        fi

        sudo mount /dev/"$device" /media
        echo "Enter side to flash [left/right]"
        read -r side
        sudo cp "$BUILDS_DIRECTORY"/zmk-"$side".uf2 /media/CURRENT.UF2
        echo "Press enter once BLUE LED has finished blinking" 
        read -r 
        sudo umount /media
        echo "Flashing complete, board can now be disconnected."
    fi
}

remote_flash() {
	sshpass -e ssh -o StrictHostKeyChecking=no "$REMOTE_USER_NAME@$REMOTE_HOST_NAME" "$(typeset -f rpi_flash); rpi_flash"
}


# setup_build_environment 
# bootloader_build
# zmk_build
rsync_flash_files
remote_flash
