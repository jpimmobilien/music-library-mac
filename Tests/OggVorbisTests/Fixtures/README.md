Testtöne, hier erzeugt (keine Fremdinhalte):

    ffmpeg -f lavfi -i "sine=frequency=1000:duration=2:sample_rate=44100" -af "volume=4,pan=stereo|c0=c0|c1=c0" -c:a libvorbis -q:a 4 tone-1k-stereo-2s.ogg
    ffmpeg -f lavfi -i "sine=frequency=440:duration=1.5:sample_rate=22050" -c:a libvorbis -q:a 0 -ac 1 tone-440-mono-22k.ogg
(Der Sinusgenerator von ffmpeg erzeugt Amplitude 1/8; volume=4 ergibt 0,5.)
