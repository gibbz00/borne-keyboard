
# Introducing the Borne Keyboard V1

Source files for the Borne Keyboard; a wireless, split, 36-key, orthogonal keyboard with a comparatively large battery capacity that should last over two months.
Also of low profile at a max height of about 17 mm (0.67 in).
Ready-made ZMK and Adafruit nrf52 bootloader binaries are placed in the `firmware/builds` directory.

**PLEASE NOTE THAT V1 IS A WORKING PROOF OF CONCEPT. Don't copy this project mindlessly and expect everything to work out of the box. I have notes containing over 500 points of improvements or cautions when working on this project, many of which are design issues to be fixed for V2.**

Kicad 6 and its component libraries are required to properly explore the majority of electronic design files. 

https://www.kicad.org/libraries/download/

Arch users simply install `kicad-library` and `kicad-library-3d-nightly` from the official repository.

# Customizing the keymap with ZMK

Customizing ZMK without having the compiler toolchain installed can be done by leveraging GitHub Actions: https://zmk.dev/docs/user-setup

I haven't yet had the time to set this up with the Borne Keyboard (coming very soon), hence the quick write-up on how to build the firmware locally.

Issues with ZMK are often covered by its official documentation or in its vibrant and welcoming discord server: https://zmk.dev/community/discord/invite

## Local builds and flashing

### Preparations

The following dependencies are required to build ZMK:
* zephyr-sdk 
* python-jsonschema
* remarshal

And for the Adafruit nRF52 bootloader:
* arm-none-eabi-gcc
* python-intelhex

For Arch Linux based distributions: All packages exist in the same name on AUR, e.g:
```
yay -S --needed python-intelhex arm-none-eabi-gcc zephyr-sdk python-jsonschema remarshal 
```

Bootloader and ZMK exist as submodules in this repository. (Not yet merged upstream.)
```
git clone URL && git submodule update
```

All firmware files unique to this keyboard are found in:
```
firmware/Adafruit_nRF52_Bootloader/src/boards/borne_keyboard/
firmware/zmk/app/boards/arm/borne-keyboard/
firmware/zmk/app/boards/shields/borne-keyboard/
```

Those only interested in updating the keymap need not look any further than:
```
firmware/zmk/app/boards/shields/borne-keyboard/borne.keymap
```

### Building ZMK

Only the left shield (half) needs to be built to update the keymap:
```
# in the firmware/zmk/app directory
west build -d build/left --pristine --board borne -- -DSHIELD=borne_left
```
### Flashing ZMK
Connect the half over USB, put it in bootloader mode (double press reset), and make sure the device storage is mounted. Then:
```
# still in the firmware/zmk/app directory
cp build/left/zephyr/zmk.uf2 path_to_borne_mass_storage/CURRENT.uf2
```

If necessary, change the occurrences of "left" to "right" to build the other half. 

### Adafruit nrf52 bootloader

Multiple ways of building and then flashing the boards over UART is explained in Joric's diligent write-up: https://github.com/joric/nrfmicro/wiki/Bootloader

I only got flashing with OpenOCD on the Raspberry Pi 4 to work.
The hardware specific `openocd.cfg` is found in the `firmware` directory.
Additional resources on how to flash the nrf5240 with OpenOCD and a Raspberry Pi 4 are found at: https://www.rototron.info/circuitpython-nrf52840-dongle-openocd-pi-tutorial/

Happy tinkering!
