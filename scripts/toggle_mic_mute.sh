#!/usr/bin/env bash

# Get the default source name
default_source_name=$(pactl get-default-source)

default_background=/home/rowan/Pictures/black.jpg
mic_off_background=/home/rowan/Pictures/blue.jpg
mic_on_background=/home/rowan/Pictures/purple.jpg

function set_background {
    background_image="$1"
    gsettings set org.gnome.desktop.background picture-uri "$background_image"
    gsettings set org.gnome.desktop.background picture-uri-dark "$background_image"
}

# Check if there are active outputs, otherwise mute and reset background
active_outputs=$(pactl list short source-outputs)
if [[ -z "$active_outputs" ]]; then
    echo hello hi
    pactl set-source-mute "$default_source_name" 1
    new_state=1
    set_background "$default_background"
    echo "No active outputs, muted all input sources."
else
    echo howdy hey
    # Toggle the mute state of the default source
    default_mute_state=$(pactl get-source-mute "$default_source_name" | awk '{print $2}')
    if [[ "$default_mute_state" == "yes" ]]; then
        pactl set-source-mute "$default_source_name" 0
        new_state=0
        set_background "$mic_on_background"
        echo "Unmuted all input sources."
    else
        pactl set-source-mute "$default_source_name" 1
        new_state=1
        echo gsettings set org.gnome.desktop.background picture-uri-dark "$mic_off_background"
        set_background "$mic_off_background"
        echo "Muted all input sources."
    fi
fi

# Set all other input sources to the same mute state as the default
while read -r source; do
    source_name=$(echo "$source" | awk '{print $2}')

    if [[ "$source_name" != "$default_source_name" ]]; then
        pactl set-source-mute "$source_name" "$new_state"
    fi
done < <(pactl list short sources)
