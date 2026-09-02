{ pkgs, devicePath }:

pkgs.stdenv.mkDerivation {
  pname = "rumble";
  version = "0.1.0";

  src = pkgs.writeText "rumble.c" ''
    #include <linux/input.h>
    #include <sys/ioctl.h>
    #include <fcntl.h>
    #include <unistd.h>

    #include <errno.h>
    #include <stdio.h>
    #include <stdlib.h>
    #include <string.h>

    #define DEVICE "${devicePath}"

    int main(int argc, char **argv)
    {
        int duration = 150;
        int strong = 65535;
        int weak = 0;

        if (argc > 1)
            duration = atoi(argv[1]);

        if (argc > 2)
            strong = atoi(argv[2]);

        if (argc > 3)
            weak = atoi(argv[3]);

        if (duration < 1 || duration > 60000 ||
            strong < 0 || strong > 65535 ||
            weak < 0 || weak > 65535) {
            fprintf(stderr,
                "usage: rumble [duration-ms] [strong] [weak]\n");
            return 2;
        }

        int fd = open(DEVICE, O_RDWR);
        if (fd < 0) {
            fprintf(stderr, "cannot open %s: %s\n",
                    DEVICE, strerror(errno));
            return 1;
        }

        struct ff_effect effect = {0};

        effect.type = FF_RUMBLE;
        effect.id = -1;
        effect.u.rumble.strong_magnitude = strong;
        effect.u.rumble.weak_magnitude = weak;
        effect.replay.length = duration;
        effect.replay.delay = 0;

        if (ioctl(fd, EVIOCSFF, &effect) < 0) {
            fprintf(stderr, "EVIOCSFF: %s\n", strerror(errno));
            close(fd);
            return 1;
        }

        struct input_event event = {0};

        event.type = EV_FF;
        event.code = effect.id;
        event.value = 1;

        if (write(fd, &event, sizeof(event)) != sizeof(event)) {
            fprintf(stderr, "failed to play rumble: %s\n",
                    strerror(errno));
            close(fd);
            return 1;
        }

        /*
         * Keep the device open until the effect has finished.
         */
        usleep((duration + 50) * 1000);

        close(fd);
        return 0;
    }

  '';

  dontUnpack = true;

  buildPhase = ''
    $CC -O2 -Wall -Wextra "$src" -o rumble
  '';

  installPhase = ''
    mkdir -p $out/bin
    cp rumble $out/bin/rumble
  '';
}
