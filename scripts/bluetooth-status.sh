#!/usr/bin/env sh

DEVICES=""

# >>> bluetoothctl info 00:16:94:0D:D4:BC
# Device 00:16:94:0D:D4:BC (public)
#         Name: Sennheiser MB Pro 2
#         Alias: SennMBPro2
#         Class: 0x00240404
#         Icon: audio-card
#         Paired: yes
#         Trusted: yes
#         Blocked: no
#         Connected: yes
#         LegacyPairing: no
#         UUID: Headset                   (00001108-0000-1000-8000-00805f9b34fb)
#         UUID: Audio Sink                (0000110b-0000-1000-8000-00805f9b34fb)
#         UUID: Advanced Audio Distribu.. (0000110d-0000-1000-8000-00805f9b34fb)
#         UUID: Handsfree                 (0000111e-0000-1000-8000-00805f9b34fb)
#         UUID: Vendor specific           (1ddce62a-ecb1-4455-8153-0743c87aec9f)
HEADSET_MAC_ADDRESS=00:16:94:0D:D4:BC
if [[ $(bluetoothctl info $HEADSET_MAC_ADDRESS | grep "Connected") == *"Connected: yes" ]]; then
    HEADSET_CONNECTED=TRUE
else
    HEADSET_CONNECTED=FALSE
fi

KEYBOARD_MAC_ADDRESS=F5:34:1F:49:35:D4
if [[ $(bluetoothctl info $KEYBOARD_MAC_ADDRESS | grep "Connected") == *"Connected: yes" ]]; then
    DEVICES="${DEVICES}|kbd"
fi

# >>> pactl list | grep 'Active Profile'
# Active Profile: output:analog-stereo+input:analog-stereo
# Active Profile: a2dp_sink_sbc
#
# >>> pactl list | grep 'Active Profile'
# Active Profile: output:analog-stereo+input:analog-stereo
# Active Profile: headset_head_unit
ACTIVE_PROFILE=$(pactl list | grep "Active Profile")
if [[ $ACTIVE_PROFILE == *"a2dp"* ]]; then
    HEADSET_PROFILE="A2DP"
elif [[ $ACTIVE_PROFILE == *"headset"* ]]; then
    HEADSET_PROFILE="HSP/HFP"
fi

if [[ $HEADSET_PROFILE ]]; then
    DEVICES="${DEVICES}|$HEADSET_PROFILE"
fi

echo ${DEVICES:1}
