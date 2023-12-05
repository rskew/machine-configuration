#!/usr/bin/env bash

# Get the default source name
default_source_name=$(pactl get-default-source)

# Toggle the mute state of the default source
default_mute_state=$(pactl get-source-mute "$default_source_name" | awk '{print $2}')
if [[ "$default_mute_state" == "yes" ]]; then
    pactl set-source-mute "$default_source_name" 0
    new_state=0
else
    pactl set-source-mute "$default_source_name" 1
    new_state=1
fi

# Set all other input sources to the same mute state as the default
while read -r source; do
    source_name=$(echo "$source" | awk '{print $2}')

    if [[ "$source_name" != "$default_source_name" ]]; then
        pactl set-source-mute "$source_name" "$new_state"
    fi
done < <(pactl list short sources)

# Notify the user
if [[ "$new_state" == "0" ]]; then
    echo "Unmuted all input sources."
else
    echo "Muted all input sources."
fi
