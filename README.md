# FFmpeg On Apple Silicon
Build ffmpeg for ARM-based Apple Silicon Macs


[![Build status](https://github.com/WeirdoArt/build-ffmpeg-on-apple-silicon/actions/workflows/blank.yml/badge.svg)](https://github.com/WeirdoArt/build-ffmpeg-on-apple-silicon/actions/workflows/blank.yml)


```bash
~ » ffmpeg -version                                                                wuwei@wuweideMacBook-Pro
ffmpeg version git-2022-07-09-a256426 Copyright (c) 2000-2022 the FFmpeg developers
built with Apple clang version 13.1.6 (clang-1316.0.21.2.5)
configuration: --prefix=/Users/wuwei/workspace/opensource/build-ffmpeg-on-apple-silicon/workdir/installdir --extra-cflags=-fno-stack-check --arch=arm64 --cc=/usr/bin/clang --pkg-config-flags=--static --enable-gpl --enable-nonfree --enable-version3 --enable-runtime-cpudetect --enable-shared --enable-fontconfig --enable-postproc --disable-doc --enable-libopus --enable-libtheora --enable-libvorbis --enable-libmp3lame --enable-libass --enable-libfreetype --enable-libx264 --enable-libx265 --enable-libvpx --enable-libaom --enable-libvidstab --enable-libsnappy --enable-sdl2 --enable-ffplay
libavutil      57. 27.100 / 57. 27.100
libavcodec     59. 36.100 / 59. 36.100
libavformat    59. 26.100 / 59. 26.100
libavdevice    59.  6.100 / 59.  6.100
libavfilter     8. 42.100 /  8. 42.100
libswscale      6.  6.100 /  6.  6.100
libswresample   4.  6.100 /  4.  6.100
libpostproc    56.  5.100 / 56.  5.100
------------------------------------------------------------------------------------------------------------
~ » ffprobe -version                                                               wuwei@wuweideMacBook-Pro
ffprobe version git-2022-07-09-a256426 Copyright (c) 2007-2022 the FFmpeg developers
built with Apple clang version 13.1.6 (clang-1316.0.21.2.5)
configuration: --prefix=/Users/wuwei/workspace/opensource/build-ffmpeg-on-apple-silicon/workdir/installdir --extra-cflags=-fno-stack-check --arch=arm64 --cc=/usr/bin/clang --pkg-config-flags=--static --enable-gpl --enable-nonfree --enable-version3 --enable-runtime-cpudetect --enable-shared --enable-fontconfig --enable-postproc --disable-doc --enable-libopus --enable-libtheora --enable-libvorbis --enable-libmp3lame --enable-libass --enable-libfreetype --enable-libx264 --enable-libx265 --enable-libvpx --enable-libaom --enable-libvidstab --enable-libsnappy --enable-sdl2 --enable-ffplay
libavutil      57. 27.100 / 57. 27.100
libavcodec     59. 36.100 / 59. 36.100
libavformat    59. 26.100 / 59. 26.100
libavdevice    59.  6.100 / 59.  6.100
libavfilter     8. 42.100 /  8. 42.100
libswscale      6.  6.100 /  6.  6.100
libswresample   4.  6.100 /  4.  6.100
libpostproc    56.  5.100 / 56.  5.100
------------------------------------------------------------------------------------------------------------
~ » ffplay -version                                                                wuwei@wuweideMacBook-Pro
ffplay version git-2022-07-09-a256426 Copyright (c) 2003-2022 the FFmpeg developers
built with Apple clang version 13.1.6 (clang-1316.0.21.2.5)
configuration: --prefix=/Users/wuwei/workspace/opensource/build-ffmpeg-on-apple-silicon/workdir/installdir --extra-cflags=-fno-stack-check --arch=arm64 --cc=/usr/bin/clang --pkg-config-flags=--static --enable-gpl --enable-nonfree --enable-version3 --enable-runtime-cpudetect --enable-shared --enable-fontconfig --enable-postproc --disable-doc --enable-libopus --enable-libtheora --enable-libvorbis --enable-libmp3lame --enable-libass --enable-libfreetype --enable-libx264 --enable-libx265 --enable-libvpx --enable-libaom --enable-libvidstab --enable-libsnappy --enable-sdl2 --enable-ffplay
libavutil      57. 27.100 / 57. 27.100
libavcodec     59. 36.100 / 59. 36.100
libavformat    59. 26.100 / 59. 26.100
libavdevice    59.  6.100 / 59.  6.100
libavfilter     8. 42.100 /  8. 42.100
libswscale      6.  6.100 /  6.  6.100
libswresample   4.  6.100 /  4.  6.100
libpostproc    56.  5.100 / 56.  5.100
```