#!/bin/bash
set -exuo pipefail

# FFmpeg for ARM-based Apple Silicon Macs

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

function build_fribidi() {
	echo "Downloading: fribidi"
	local download_url=$(curl -s https://api.github.com/repos/fribidi/fribidi/releases/latest | jq '.assets[0].browser_download_url')
	echo "${download_url}"
	{ (curl -L -o - ${download_url} | tar Jxf - -C $CMPLD/) & }
	wait
	local filename=$(basename $download_url)
	local dirname=${filename//.tar.*z\"/}
	if [[ ! -e "${SRC}/lib/pkgconfig/fribidi.pc" ]]; then
		echo '♻️ ' Start compiling FRIBIDI
		cd ${CMPLD}/${dirname}
		./configure --prefix=${SRC} --disable-debug --disable-dependency-tracking \
			--disable-silent-rules --disable-shared --enable-static
		make -j ${NUM_PARALLEL_BUILDS}
		make install
	fi
}
build_fribidi

function build_yasm() {
	if [[ ! -e "${SRC}/lib/libyasm.a" ]]; then
		echo '♻️ ' Start compiling YASM
		cd ${CMPLD}
		cd yasm-1.3.0
		./configure --prefix=${SRC}
		make -j ${NUM_PARALLEL_BUILDS}
		make install
	fi
}

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
	if [[ ! -e "${SRC}/bin/nasm" ]]; then
		echo '♻️ ' Start compiling NASM
		#
		# compile NASM
		#
		cd ${CMPLD}
		cd nasm-2.15.05
		./configure --prefix=${SRC}
		make -j ${NUM_PARALLEL_BUILDS}
		make install
	fi
}

function build_pkgconfig() {
	if [[ ! -e "${SRC}/bin/pkg-config" ]]; then
		echo '♻️ ' Start compiling pkg-config
		cd ${CMPLD}
		cd pkg-config-0.29.2
		export LDFLAGS="-framework Foundation -framework Cocoa"
		./configure --prefix=${SRC} --with-pc-path=${SRC}/lib/pkgconfig --with-internal-glib --disable-shared --enable-static
		make -j ${NUM_PARALLEL_BUILDS}
		make install
		unset LDFLAGS
	fi
}

function build_zlib() {
	if [[ ! -e "${SRC}/lib/pkgconfig/zlib.pc" ]]; then
		echo '♻️ ' Start compiling ZLIB
		cd ${CMPLD}
		cd zlib-1.2.11
		./configure --prefix=${SRC}
		make -j ${NUM_PARALLEL_BUILDS}
		make install
		rm ${SRC}/lib/libz.so* || true
		rm ${SRC}/lib/libz.* || true
	fi
}

function build_lame() {
	if [[ ! -e "${SRC}/lib/libmp3lame.a" ]]; then
		cd ${CMPLD}
		cd lame
		./configure --prefix=${SRC} --disable-shared --enable-static
		make -j ${NUM_PARALLEL_BUILDS}
		make install
	fi
}

function build_x264() {
	if [[ ! -e "${SRC}/lib/pkgconfig/x264.pc" ]]; then
		echo '♻️ ' Start compiling X264
		cd ${CMPLD}
		cd x264
		./configure --prefix=${SRC} --disable-shared --enable-static --enable-pic
		make -j ${NUM_PARALLEL_BUILDS}
		make install
		make install-lib-static
	fi
}

function build_x265() {
	if [[ ! -e "${SRC}/lib/pkgconfig/x265.pc" ]]; then
		echo '♻️ ' Start compiling X265
		rm -f ${SRC}/include/x265*.h 2>/dev/null
		rm -f ${SRC}/lib/libx265.a 2>/dev/null

		echo '♻️ ' X265 12bit
		cd ${CMPLD}
		cd x265_3.3/source
		cmake -DCMAKE_INSTALL_PREFIX:PATH=${SRC} -DHIGH_BIT_DEPTH=ON -DMAIN12=ON -DENABLE_SHARED=NO -DEXPORT_C_API=NO -DENABLE_CLI=OFF .
		make -j ${NUM_PARALLEL_BUILDS}
		mv libx265.a libx265_main12.a
		make clean-generated
		rm CMakeCache.txt

		echo '♻️ ' X265 10bit
		cd ${CMPLD}
		cd x265_3.3/source
		cmake -DCMAKE_INSTALL_PREFIX:PATH=${SRC} -DMAIN10=ON -DHIGH_BIT_DEPTH=ON -DENABLE_SHARED=NO -DEXPORT_C_API=NO -DENABLE_CLI=OFF .
		make clean
		make -j ${NUM_PARALLEL_BUILDS}
		mv libx265.a libx265_main10.a
		make clean-generated && rm CMakeCache.txt

		echo '♻️ ' X265 full
		cd ${CMPLD}
		cd x265_3.3/source
		cmake -DCMAKE_INSTALL_PREFIX:PATH=${SRC} -DEXTRA_LIB="x265_main10.a;x265_main12.a" -DEXTRA_LINK_FLAGS=-L. -DLINKED_12BIT=ON -DLINKED_10BIT=ON -DENABLE_SHARED=OFF -DENABLE_CLI=OFF .
		make clean
		make -j ${NUM_PARALLEL_BUILDS}

		mv libx265.a libx265_main.a
		libtool -static -o libx265.a libx265_main.a libx265_main10.a libx265_main12.a 2>/dev/null
		make install
	fi
}

function build_vpx() {
	if [[ ! -e "${SRC}/lib/pkgconfig/vpx.pc" ]]; then
		echo '♻️ ' Start compiling VPX
		cd ${CMPLD}
		cd libvpx
		./configure --prefix=${SRC} --enable-vp8 --enable-postproc --enable-vp9-postproc --enable-vp9-highbitdepth --disable-examples --disable-docs --enable-multi-res-encoding --disable-unit-tests --enable-pic --disable-shared
		make -j ${NUM_PARALLEL_BUILDS}
		make install
	fi
}

function build_expat() {
	if [[ ! -e "${SRC}/lib/pkgconfig/expat.pc" ]]; then
		echo '♻️ ' Start compiling EXPAT
		cd ${CMPLD}
		cd expat-2.2.10
		./configure --prefix=${SRC} --disable-shared --enable-static
		make -j ${NUM_PARALLEL_BUILDS}
		make install
	fi
}

function build_libiconv() {
	if [[ ! -e "${SRC}/lib/libiconv.a" ]]; then
		echo '♻️ ' Start compiling LIBICONV
		cd ${CMPLD}
		cd libiconv-1.16
		./configure --prefix=${SRC} --disable-shared --enable-static
		make -j ${NUM_PARALLEL_BUILDS}
		make install
	fi
}

function build_enca() {
	if [[ ! -d "${SRC}/libexec/enca" ]]; then
		echo '♻️ ' Start compiling ENCA
		cd ${CMPLD}
		cd enca-1.19
		./configure --prefix=${SRC} --disable-dependency-tracking --disable-shared --enable-static
		make -j ${NUM_PARALLEL_BUILDS}
		make install
	fi
}

function build_freetype() {
	#if [[ ! -e "${SRC}/lib/pkgconfig/freetype2.pc" ]]; then
	echo '♻️ ' Start compiling FREETYPE
	cd ${CMPLD}
	cd freetype-2.10.4
	./configure --prefix=${SRC} --disable-shared --enable-static
	make -j ${NUM_PARALLEL_BUILDS}
	make install
	#fi
}

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

total_start_time="$(date -u +%s)"
#build_yasm
#build_aom
#build_nasm
#build_pkgconfig
#build_zlib
#build_lame
#build_x264
#build_x265
#build_vpx
#build_expat
#build_libiconv
#build_enca
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
#total_end_time="$(date -u +%s)"
#total_elapsed="$(($total_end_time-$total_start_time))"
echo "Total $total_elapsed seconds elapsed for build"
