#! /usr/bin/env bash

## Usage on system using systemd:
##  systemd-run --user --on-calendar="Mon 2017-05-08 23:53:00 AEST" wakeup.sh


# List of songs to randomly select from
SONGS=(
## The Cure - Just Like Heaven
#https://www.youtube.com/watch?v=8Dhn_iIQXDE
## Cyberpunk Bartender Action OST - A Neon Glow Lights The Way
#https://www.youtube.com/watch?v=i_ABeAKx9vw
## Gigi Masin - Clouds
#https://www.youtube.com/watch?v=tVz19M9JoRA
## Cyberpunk Bartender Action OST - A. Rene
#https://www.youtube.com/watch?v=X6k8mAUfyGU
### Bruce Springsteen - Born to Run
##https://www.youtube.com/watch?v=f3t9SfrfDZM
# Twerps - Coast to Coast
https://www.youtube.com/watch?v=ZotqbxM-0-k
## Actress - N.E.W.
#https://www.youtube.com/watch?v=eJNfzy88oK8
## Jon Hopkins - Light Through the Veins
#https://www.youtube.com/watch?v=bazz7A_tD0g
### Jobim - Stone Flower (album)
##https://www.youtube.com/watch?v=7U8TjDsnVcE
## Kito Jempere - Typewriter (HNNY remix)
#https://www.youtube.com/watch?v=S_p2pZizRPk
## Laraaji - Unicorns in Paradise
#https://www.youtube.com/watch?v=pwJtCY_R-5E
## Aziza Brahim - Lagi
#https://www.youtube.com/watch?v=g-_i0if61lA
## Kurt Vile - Wakin on a Pretty Daze
#https://www.youtube.com/watch?v=bd0K76H7sU8
## Pantha Du Prince - Lay In A Shimmer
#https://www.youtube.com/watch?v=AVmwuoXIn8w
## Peter Schilling - Major Tom
#https://www.youtube.com/watch?v=N1Hs2AQwDgA
## ELO - Don't Bring Me Down
#https://www.youtube.com/watch?v=KYh7PwDo3Iw
## Semiomime - Cobweb
#https://www.youtube.com/watch?v=qrIy8aZ4AAI
)


export DISPLAY=:0
# Change to absolute path to .Xauth
export XAUTHORITY="/home/rowan/.Xauthority"

# Change path to script to local absolute path
ROOMNOISE=$(~/documents/code/scripts/getroombackgroundnoise.sh)
echo "Playback volume: $ROOMNOISE%"
#amixer set Master "$ROOMNOISE"%

SONGPICK=$(expr $RANDOM % ${#SONGS[@]})
SONGERISM=${SONGS[$SONGPICK]}
chromium $SONGERISM

#qsynth -s -a jack &
#sleep 5
#swipl /home/rowan/documents/code/Prolog/music/music.pl
