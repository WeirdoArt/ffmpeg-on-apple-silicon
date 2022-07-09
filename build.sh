#!/usr/bin/env bash
set -exuo pipefail

# FFmpeg for ARM-based Apple Silicon Macs

total_start_time="$(date -u +%s)"

WORKDIR="$(pwd)/workdir"
mkdir -p ${WORKDIR}

SRC="$WORKDIR/installdir"
CMPLD="$WORKDIR/compile"
NUM_PARALLEL_BUILDS=$(sysctl -n hw.ncpu)

# if [[ -e "${CMPLD}" ]]; then
#   rm -rf "${CMPLD}"
# fi

mkdir -p ${SRC}
mkdir -p ${CMPLD}

export PATH=${SRC}/bin:$PATH
export CC=clang
export CXX=clang++
export PKG_CONFIG_PATH="${SRC}/lib/pkgconfig"
export MACOSX_DEPLOYMENT_TARGET=11.0

if [[ "$(uname -m)" == "arm64" ]]; then
	export ARCH=arm64
else
	export ARCH=x86_64
fi

export LDFLAGS=${LDFLAGS:-}
export CFLAGS=${CFLAGS:-}

function check_package() {
	if [[ "$ARCH" == "arm64" ]]; then
		if [[ ! -e "/opt/homebrew/opt/$1" ]]; then
			echo "Installing $1 using Homebrew"
			brew install "$1"
			export LDFLAGS="-L/opt/homebrew/opt/$1/lib ${LDFLAGS}"
			export CFLAGS="-I/opt/homebrew/opt/$1/include ${CFLAGS}"
			export PKG_CONFIG_PATH="$PKG_CONFIG_PATH:/opt/homebrew/opt/$1/lib/pkgconfig"
		fi
	else
		if [[ ! -e "/usr/local/opt/$1" ]]; then
			echo "Installing $1 using Homebrew"
			brew install "$1"
			export LDFLAGS="-L/usr/local/opt/$1/lib ${LDFLAGS}"
			export CFLAGS="-I/usr/local/opt/$1/include ${CFLAGS}"
			export PKG_CONFIG_PATH="$PKG_CONFIG_PATH:/usr/local/opt/$1/lib/pkgconfig"
		fi
	fi
}
check_package pkgconfig
check_package libtool
check_package glib

if ! command -v autoreconf &>/dev/null; then
	brew install autoconf
fi
if ! command -v automake &>/dev/null; then
	brew install automake
fi
if ! command -v cmake &>/dev/null; then
	brew install cmake
fi

echo "Cloning required git repositories"
git clone --depth 1 -b master https://code.videolan.org/videolan/x264.git $CMPLD/x264 &
git clone --depth 1 -b origin https://github.com/rbrito/lame.git $CMPLD/lame &
git clone --depth 1 -b master https://github.com/webmproject/libvpx $CMPLD/libvpx &
git clone --depth 1 -b master https://github.com/FFmpeg/FFmpeg $CMPLD/ffmpeg &
# git clone --depth 1 -b v2.0.1 https://aomedia.googlesource.com/aom.git $CMPLD/aom &
wait

function download_3rdparty_packet() {
	# args: 1-filename 2-version 3-packet_type 4-download_url
	local filename=$1
	local version=$2
	local packet_type=$3
	local tmp=$4
	local split_url=$(echo $tmp | awk -F "/" '{print $NF}')
	if [[ "${split_url}" == "version" ]]; then
		local download_url=${tmp/%version/$version}/${filename}-${version}.tar.$3
	else
		local download_url=$4/${filename}-${version}.tar.$3
	fi
	
	if [ ! -d "$CMPLD/${filename}-${version}" ]; then
		echo "Downloading: ${filename} ($version)"
		{ (curl -Ls -o - ${download_url} | tar zxf - -C $CMPLD/) & }
		wait
	fi
}

function build_fribidi() {
	local download_url=$(curl -s https://api.github.com/repos/fribidi/fribidi/releases/latest | jq -r '.assets[0].browser_download_url')
	local tarball_type=$(echo "$download_url" | awk -F "." '{print $NF}')
	local filename=$(basename $download_url ".tar.$tarball_type")
	local version=$(echo "$filename" | awk -F "-" '{print $NF}')

	if [ ! -d "$CMPLD/$filename" ]; then
		echo "Downloading: fribidi ($version)"
		{ (curl -Ls -o - ${download_url} | tar Jxf - -C $CMPLD/) & }
		wait
	fi

	if [[ ! -e "${SRC}/lib/pkgconfig/fribidi.pc" ]]; then
		echo '♻️ ' Start compiling FRIBIDI
		cd ${CMPLD}/${filename}
		./configure --prefix=${SRC} --disable-debug --disable-dependency-tracking \
			--disable-silent-rules --disable-shared --enable-static
		make -j ${NUM_PARALLEL_BUILDS}
		make install
	fi
}
build_fribidi

function build_yasm() {
	local filename=yasm-1.3.0
	download_3rdparty_packet yasm 1.3.0 gz http://www.tortall.net/projects/yasm/releases
	if [[ ! -e "${SRC}/lib/libyasm.a" ]]; then
		echo '♻️ ' Start compiling YASM
		cd ${CMPLD}/${filename}
		./configure --prefix=${SRC}
		make -j ${NUM_PARALLEL_BUILDS}
		make install
	fi
}
build_yasm

function build_aom() {
	if [[ ! -e "${SRC}/lib/pkgconfig/aom.pc" ]]; then
		echo '♻️ ' Start compiling AOM
		cd ${CMPLD}
		cd aom
		mkdir aom_build
		cd aom_build

		AOM_CMAKE_PARAMS="-DENABLE_DOCS=off -DENABLE_EXAMPLES=off -DENABLE_TESTDATA=off -DENABLE_TESTS=off -DENABLE_TOOLS=off -DCMAKE_INSTALL_PREFIX:PATH=${SRC} -DLIBTYPE=STATIC"
		if [[ "$ARCH" == "arm64" ]]; then
			AOM_CMAKE_PARAMS="$AOM_CMAKE_PARAMS -DCONFIG_RUNTIME_CPU_DETECT=0"
		fi
		cmake ${CMPLD}/aom $AOM_CMAKE_PARAMS
		make -j ${NUM_PARALLEL_BUILDS}
		make install
	fi
}

function build_nasm() {
	local filename=nasm-2.15.05
	download_3rdparty_packet nasm 2.15.05 gz https://www.nasm.us/pub/nasm/releasebuilds/version
	if [[ ! -e "${SRC}/bin/nasm" ]]; then
		echo '♻️ ' Start compiling NASM
		cd ${CMPLD}/${filename}
		./configure --prefix=${SRC}
		make -j ${NUM_PARALLEL_BUILDS}
		make install
	fi
}
build_nasm

function build_pkgconfig() {
	local filename=pkg-config-0.29.2
	download_3rdparty_packet pkg-config 0.29.2 gz https://pkg-config.freedesktop.org/releases
	if [[ ! -e "${SRC}/bin/pkg-config" ]]; then
		echo '♻️ ' Start compiling pkg-config
		cd ${CMPLD}/${filename}
		export LDFLAGS="-framework Foundation -framework Cocoa"
		./configure --prefix=${SRC} --with-pc-path=${SRC}/lib/pkgconfig --with-internal-glib --disable-shared --enable-static
		make -j ${NUM_PARALLEL_BUILDS}
		make install
		unset LDFLAGS
	fi
}
build_pkgconfig

function build_zlib() {
	local filename=zlib-1.2.12
	download_3rdparty_packet zlib 1.2.12 gz https://zlib.net/fossils
	if [[ ! -e "${SRC}/lib/pkgconfig/zlib.pc" ]]; then
		echo '♻️ ' Start compiling ZLIB
		cd ${CMPLD}/${filename}
		./configure --prefix=${SRC}
		make -j ${NUM_PARALLEL_BUILDS}
		make install
		rm ${SRC}/lib/libz.so* || true
		rm ${SRC}/lib/libz.* || true
	fi
}
build_zlib

function build_lame() {
	if [[ ! -e "${SRC}/lib/libmp3lame.a" ]]; then
		echo '♻️ ' Start lame
		cd ${CMPLD}/lame
		./configure --prefix=${SRC} --disable-shared --enable-static
		make -j ${NUM_PARALLEL_BUILDS}
		make install
	fi
}
build_lame

function build_x264() {
	if [[ ! -e "${SRC}/lib/pkgconfig/x264.pc" ]]; then
		echo '♻️ ' Start compiling X264
		cd ${CMPLD}/x264
		./configure --prefix=${SRC} --disable-shared --enable-static --enable-pic
		make -j ${NUM_PARALLEL_BUILDS}
		make install
		make install-lib-static
	fi
}
build_x264

function build_x265() {
	local filename="x265_3.3"
	if [ ! -d "$CMPLD/$filename" ]; then
		echo "Downloading: x265 (3.3)"
		{ (curl -Ls -o - https://bitbucket.org/multicoreware/x265_git/downloads/${filename}.tar.gz | tar zxf - -C $CMPLD/ &) & }
		wait
	fi
	if [[ ! -e "${SRC}/lib/pkgconfig/x265.pc" ]]; then
		echo '♻️ ' Start compiling X265
		rm -f ${SRC}/include/x265*.h 2>/dev/null
		rm -f ${SRC}/lib/libx265.a 2>/dev/null

		echo '♻️ ' X265 12bit
		cd ${CMPLD}/x265_3.3/source
		cmake -DCMAKE_INSTALL_PREFIX:PATH=${SRC} -DHIGH_BIT_DEPTH=ON -DMAIN12=ON -DENABLE_SHARED=NO -DEXPORT_C_API=NO -DENABLE_CLI=OFF .
		make -j ${NUM_PARALLEL_BUILDS}
		mv libx265.a libx265_main12.a
		make clean-generated
		rm CMakeCache.txt

		echo '♻️ ' X265 10bit
		cd ${CMPLD}/x265_3.3/source
		cmake -DCMAKE_INSTALL_PREFIX:PATH=${SRC} -DMAIN10=ON -DHIGH_BIT_DEPTH=ON -DENABLE_SHARED=NO -DEXPORT_C_API=NO -DENABLE_CLI=OFF .
		make clean
		make -j ${NUM_PARALLEL_BUILDS}
		mv libx265.a libx265_main10.a
		make clean-generated && rm CMakeCache.txt

		echo '♻️ ' X265 full
		cd ${CMPLD}/x265_3.3/source
		cmake -DCMAKE_INSTALL_PREFIX:PATH=${SRC} -DEXTRA_LIB="x265_main10.a;x265_main12.a" -DEXTRA_LINK_FLAGS=-L. -DLINKED_12BIT=ON -DLINKED_10BIT=ON -DENABLE_SHARED=OFF -DENABLE_CLI=OFF .
		make clean
		make -j ${NUM_PARALLEL_BUILDS}

		mv libx265.a libx265_main.a
		libtool -static -o libx265.a libx265_main.a libx265_main10.a libx265_main12.a 2>/dev/null
		make install
	fi
}
build_x265

function build_vpx() {
	if [[ ! -e "${SRC}/lib/pkgconfig/vpx.pc" ]]; then
		echo '♻️ ' Start compiling VPX
		cd ${CMPLD}/libvpx
		./configure --prefix=${SRC} --enable-vp8 --enable-postproc --enable-vp9-postproc --enable-vp9-highbitdepth --disable-examples --disable-docs --enable-multi-res-encoding --disable-unit-tests --enable-pic --disable-shared
		make -j ${NUM_PARALLEL_BUILDS}
		make install
	fi
}
build_vpx

function build_expat() {
	local download_url=$(curl -s https://api.github.com/repos/libexpat/libexpat/releases/latest | jq -r '.assets[0].browser_download_url')
	local tarball_type=$(echo "$download_url" | awk -F "." '{print $NF}')
	local filename=$(basename $download_url ".tar.$tarball_type")
	local version=$(echo "$filename" | awk -F "-" '{print $NF}')

	if [ ! -d "$CMPLD/$filename" ]; then
		echo "Downloading: expat ($version)"
		{ (curl -L -o - ${download_url} | tar Jxf - -C $CMPLD/) & }
		wait
	fi

	if [[ ! -e "${SRC}/lib/pkgconfig/expat.pc" ]]; then
		echo '♻️ ' Start compiling EXPAT
		cd ${CMPLD}/$filename
		./configure --prefix=${SRC} --disable-shared --enable-static
		make -j ${NUM_PARALLEL_BUILDS}
		make install
	fi
}
build_expat

function build_libiconv() {
	local filename=libiconv-1.17
	download_3rdparty_packet libiconv 1.17 gz https://ftp.gnu.org/pub/gnu/libiconv
	if [[ ! -e "${SRC}/lib/libiconv.a" ]]; then
		echo '♻️ ' Start compiling LIBICONV
		cd ${CMPLD}/${filename}
		./configure --prefix=${SRC} --disable-shared --enable-static
		make -j ${NUM_PARALLEL_BUILDS}
		make install
	fi
}
build_libiconv

function build_enca() {
	local filename=enca-1.19
	download_3rdparty_packet enca 1.19 gz https://dl.cihar.com/enca
	if [[ ! -d "${SRC}/libexec/enca" ]]; then
		echo '♻️ ' Start compiling ENCA
		cd ${CMPLD}/${filename}
		./configure --prefix=${SRC} --disable-dependency-tracking --disable-shared --enable-static
		make -j ${NUM_PARALLEL_BUILDS}
		make install
	fi
}
build_enca

function build_freetype() {
	local filename=freetype-2.10.4
	download_3rdparty_packet freetype 2.10.4 gz https://download.savannah.gnu.org/releases/freetype
	if [[ ! -e "${SRC}/lib/pkgconfig/freetype2.pc" ]]; then
		echo '♻️ ' Start compiling FREETYPE
		cd ${CMPLD}/${filename}
		./configure --prefix=${SRC} --disable-shared --enable-static
		make -j ${NUM_PARALLEL_BUILDS}
		make install
	fi
}
build_freetype

function build_gettext() {
	if [[ ! -e "${SRC}/lib/pkgconfig/gettext.pc" ]]; then
		echo '♻️ ' Start compiling gettext
		cd ${CMPLD}
		cd gettext-0.21
		./configure --prefix=${SRC} --disable-dependency-tracking --disable-silent-rules --disable-debug --disable-shared --enable-static \
			--with-included-gettext --with-included-glib --with-includedlibcroco --with-included-libunistring --with-emacs \
			--disable-java --disable-csharp --without-git --without-cvs --without-xz
		make -j ${NUM_PARALLEL_BUILDS}
		make install
	fi
}

function build_fontconfig() {
	if [[ ! -e "${SRC}/lib/pkgconfig/fontconfig.pc" ]]; then
		echo '♻️ ' Start compiling FONTCONFIG
		cd ${CMPLD}
		cd fontconfig-2.13.93
		./configure --prefix=${SRC} --enable-iconv --disable-libxml2 --disable-shared --enable-static --disable-docs
		make -j ${NUM_PARALLEL_BUILDS}
		make install
	fi
}

function build_harfbuzz() {
	if [[ ! -e "${SRC}/lib/pkgconfig/harfbuzz.pc" ]]; then
		echo '♻️ ' Start compiling harfbuzz
		cd ${CMPLD}
		cd harfbuzz-2.7.2
		./configure --prefix=${SRC} --disable-shared --enable-static
		make -j ${NUM_PARALLEL_BUILDS}
		make install
	fi
}

function build_ass() {
	if [[ ! -e "${SRC}/lib/pkgconfig/libass.pc" ]]; then
		cd ${CMPLD}
		cd libass-0.16.0
		#autoreconf -i
		./configure --prefix=${SRC} --disable-dependency-tracking --disable-shread --enable-static
		make -j ${NUM_PARALLEL_BUILDS}
		make install
	fi
}

function build_opus() {
	if [[ ! -e "${SRC}/lib/pkgconfig/opus.pc" ]]; then
		echo '♻️ ' Start compiling OPUS
		cd ${CMPLD}
		cd opus-1.3.1
		./configure --prefix=${SRC} --disable-shared --enable-static
		make -j ${NUM_PARALLEL_BUILDS}
		make install
	fi
}

function build_ogg() {
	if [[ ! -e "${SRC}/lib/pkgconfig/ogg.pc" ]]; then
		echo '♻️ ' Start compiling LIBOGG
		cd ${CMPLD}
		cd libogg-1.3.4
		patch -p1 <./fix_unsigned_typedefs.patch
		./configure --prefix=${SRC} --disable-shared --enable-static
		make -j ${NUM_PARALLEL_BUILDS}
		make install
	fi
}

function build_vorbis() {
	if [[ ! -e "${SRC}/lib/pkgconfig/vorbis.pc" ]]; then
		echo '♻️ ' Start compiling LIBVORBIS
		cd ${CMPLD}
		cd libvorbis-1.3.7
		./configure --prefix=${SRC} --with-ogg-libraries=${SRC}/lib --with-ogg-includes=${SRC}/include/ --enable-static --disable-shared --build=x86_64
		make -j ${NUM_PARALLEL_BUILDS}
		make install
	fi
}

function build_theora() {
	if [[ ! -e "${SRC}/lib/pkgconfig/theora.pc" ]]; then
		echo '♻️ ' Start compiling THEORA
		cd ${CMPLD}
		cd libtheora-1.1.1
		./configure --prefix=${SRC} --disable-asm --with-ogg-libraries=${SRC}/lib --with-ogg-includes=${SRC}/include/ --with-vorbis-libraries=${SRC}/lib --with-vorbis-includes=${SRC}/include/ --enable-static --disable-shared
		make -j ${NUM_PARALLEL_BUILDS}
		make install
	fi
}

function build_vidstab() {
	# https://github.com/georgmartius/vid.stab
	if [[ ! -e "${SRC}/lib/pkgconfig/vidstab.pc" ]]; then
		echo '♻️ ' Start compiling Vid-stab
		cd ${CMPLD}
		cd vid.stab-1.1.0
		patch -p1 <fix_cmake_quoting.patch
		cmake . -DCMAKE_INSTALL_PREFIX:PATH=${SRC} -DLIBTYPE=STATIC -DBUILD_SHARED_LIBS=OFF -DUSE_OMP=OFF -DENABLE_SHARED=off
		make -j ${NUM_PARALLEL_BUILDS}
		make install
	fi
}

function build_snappy() {
	if [[ ! -e "${SRC}/lib/libsnappy.a" ]]; then
		echo '♻️ ' Start compiling Snappy
		cd ${CMPLD}
		cd snappy-1.1.8
		cmake . -DCMAKE_INSTALL_PREFIX:PATH=${SRC} -DLIBTYPE=STATIC -DENABLE_SHARED=off
		make -j ${NUM_PARALLEL_BUILDS}
		make install
	fi
}
function build_sdl() {
	if [[ ! -e "${SRC}/lib/pkgconfig/sdl2.pc" ]]; then
		echo '♻️ ' Start compiling SDL
		cd ${CMPLD}
		cd SDL
		cmake . -Bbuild -DCMAKE_INSTALL_PREFIX:PATH=${SRC} -DLIBTYPE=STATIC -DBUILD_SHARED_LIBS=OFF -DUSE_OMP=OFF -DENABLE_SHARED=OFF
		make -C ./build -j ${NUM_PARALLEL_BUILDS}
		make install
	fi
}

function build_ffmpeg() {
	echo '♻️ ' Start compiling FFMPEG
	cd ${CMPLD}
	cd FFmpeg
	export LDFLAGS="-L${SRC}/lib ${LDFLAGS:-}"
	export CFLAGS="-I${SRC}/include ${CFLAGS:-}"
	export LDFLAGS="$LDFLAGS -lexpat -lenca -lfribidi -liconv -lstdc++ -lfreetype -framework CoreText -framework VideoToolbox"
	./configure --prefix=${SRC} --extra-cflags="-fno-stack-check" --arch=${ARCH} --cc=/usr/bin/clang \
		--enable-gpl --enable-version3 --pkg-config-flags=--static --enable-ffplay \
		--enable-postproc --enable-nonfree --enable-runtime-cpudetect --enable-shared
	echo "build start"
	start_time="$(date -u +%s)"
	make -j ${NUM_PARALLEL_BUILDS}
	end_time="$(date -u +%s)"
	elapsed="$(($end_time - $start_time))"
	make install
	echo "[FFmpeg] $elapsed seconds elapsed for build"
}

#build_aom
#build_freetype
#if [[ "$ARCH" == "arm64" ]]; then
#  build_gettext
#fi
#build_fontconfig
#build_harfbuzz
#build_ass
#build_opus
#build_ogg
#uild_vorbis
#build_theora
#build_vidstab
#build_snappy
#build_sdl
#build_ffmpeg
total_end_time="$(date -u +%s)"
total_elapsed="$(($total_end_time-$total_start_time))"
echo "Total $total_elapsed seconds elapsed for build"
