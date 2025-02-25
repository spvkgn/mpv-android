#!/bin/bash -e

. ./include/depinfo.sh

[ -z "$IN_CI" ] && IN_CI=0
[ -z "$WGET" ] && WGET=wget

mkdir -p deps && cd deps

# mbedtls
if [ ! -d mbedtls ]; then
	mkdir mbedtls
	$WGET https://github.com/Mbed-TLS/mbedtls/releases/download/mbedtls-$v_mbedtls/mbedtls-$v_mbedtls.tar.bz2 -O - | \
		tar -xj -C mbedtls --strip-components=1
fi

# dav1d
[ ! -d dav1d ] && git clone https://github.com/videolan/dav1d

# ffmpeg
if [ ! -d ffmpeg ]; then
	git clone https://github.com/FFmpeg/FFmpeg ffmpeg
	[ $IN_CI -eq 1 ] && git -C ffmpeg checkout $v_ci_ffmpeg
	# https://github.com/mpv-player/mpv/pull/15612
	$WGET https://patchwork.ffmpeg.org/project/ffmpeg/patch/20250329222809.606230-2-ffmpeg@fratti.ch/raw/ -O - | \
		patch --verbose -d ffmpeg -p1
fi

# freetype2
[ ! -d freetype2 ] && git clone --recurse-submodules https://gitlab.freedesktop.org/freetype/freetype.git freetype2 -b VER-${v_freetype//./-}

# fribidi
if [ ! -d fribidi ]; then
	mkdir fribidi
	$WGET https://github.com/fribidi/fribidi/releases/download/v$v_fribidi/fribidi-$v_fribidi.tar.xz -O - | \
		tar -xJ -C fribidi --strip-components=1
fi

# harfbuzz
if [ ! -d harfbuzz ]; then
	mkdir harfbuzz
	$WGET https://github.com/harfbuzz/harfbuzz/releases/download/$v_harfbuzz/harfbuzz-$v_harfbuzz.tar.xz -O - | \
		tar -xJ -C harfbuzz --strip-components=1
fi

# unibreak
if [ ! -d unibreak ]; then
	mkdir unibreak
	$WGET https://github.com/adah1972/libunibreak/releases/download/libunibreak_${v_unibreak//./_}/libunibreak-${v_unibreak}.tar.gz -O - | \
		tar -xz -C unibreak --strip-components=1
fi

# libass
[ ! -d libass ] && git clone https://github.com/libass/libass

# lua
if [ ! -d lua ]; then
	mkdir lua
	$WGET https://www.lua.org/ftp/lua-$v_lua.tar.gz -O - | \
		tar -xz -C lua --strip-components=1
fi

# libplacebo
[ ! -d libplacebo ] && git clone --recursive https://github.com/haasn/libplacebo

# mpv
[ ! -d mpv ] && git clone https://github.com/mpv-player/mpv
( cd mpv && gh pr diff 15612 -R mpv-player/mpv | git apply - )

cd ..

# youtube-dl
$WGET https://kitsunemimi.pw/ytdl/dist.zip
unzip dist.zip -d ../app/src/main/assets/ytdl
rm -f ../app/src/main/assets/ytdl/youtube-dl # don't need it
rm dist.zip
# python for arm64
$WGET https://github.com/spvkgn/ndk-pkg-package-manually-build/releases/download/python3.9-release/python3-3.9.22-android-21-arm64-v8a.release.tar.xz -O - | \
	tar -C ../app/src/main/assets/ytdl --strip-components=2 --transform='s/python3\.[0-9]/python3/' --wildcards -xJvf - */bin/python3.9
chmod -x ../app/src/main/assets/ytdl/python3
