#!/bin/bash -e

# go to buildscripts root folder
cd "$( dirname "${BASH_SOURCE[0]}" )/.."

. ./include/depinfo.sh

msg() {
	printf '==> %s\n' "$1"
}

fetch_prefix() {
	if [[ "$CACHE_MODE" == folder ]]; then
		local text=
		if [ -f "$CACHE_FOLDER/id.txt" ]; then
			text=$(cat "$CACHE_FOLDER/id.txt")
		else
			echo "Cache seems to be empty"
		fi
		printf 'Expecting "%s",\nfound     "%s".\n' "$ci_tarball" "$text"
		if [[ "$text" == "$ci_tarball" ]]; then
			tar -xzf "$CACHE_FOLDER/data.tgz" -C prefix && return 0
		fi
	fi
	return 1
}

build_prefix() {
	msg "Building the prefix ($ci_tarball)..."

	msg "Fetching deps"
	IN_CI=1 ./include/download-deps.sh

	# build everything mpv depends on (but not mpv itself)
	for x in ${dep_mpv[@]}; do
		msg "Building $x"
		./buildall.sh $x
	done

	if [[ "$CACHE_MODE" == folder && -w "$CACHE_FOLDER" ]]; then
		msg "Compressing the prefix"
		tar -cvzf "$CACHE_FOLDER/data.tgz" -C prefix .
		echo "$ci_tarball" >"$CACHE_FOLDER/id.txt"
	fi
}

export WGET="wget --progress=bar:force"

if [ "$1" = "export" ]; then
	# export variable with unique cache identifier
	echo "CACHE_IDENTIFIER=$ci_tarball"
	exit 0
elif [ "$1" = "install" ]; then
	# install deps
	if [[ -n "$ANDROID_HOME" && -d "$ANDROID_HOME" ]]; then
		msg "Linking existing SDK"
		mkdir -p sdk
		ln -sv "$ANDROID_HOME" sdk/android-sdk-linux
	fi

	msg "Fetching SDK + NDK"
	IN_CI=1 ./include/download-sdk.sh

	msg "Fetching mpv"
	mkdir -p deps/mpv
	gh api repos/mpv-player/mpv/releases/latest --jq '.tag_name' | \
		xargs -I{} $WGET https://github.com/mpv-player/mpv/archive/refs/tags/{}.tar.gz -O - | tar -xz -C deps/mpv --strip-components=1
	$WGET --header="Authorization: token $GH_TOKEN" https://patch-diff.githubusercontent.com/raw/mpv-player/mpv/pull/15612.diff -O - | \
		patch --verbose -d deps/mpv -p1

	msg "Trying to fetch existing prefix"
	mkdir -p prefix
	fetch_prefix || build_prefix
	exit 0
elif [ "$1" = "build" ]; then
	# run build
	:
else
	exit 1
fi

msg "Fetching python"
mkdir -p $HOME/dist

gh api repos/spvkgn/ndk-pkg-package-manually-build/releases/tags/python${PY_VERSION}-release --jq '.assets[] | select(.name | startswith("python3") and endswith("'"$ABI"'.release.tar.xz")) | .browser_download_url' | \
xargs -I{} wget --header="Authorization: token $GH_TOKEN" {} -O - | tee \
  >(tar -C ../app/src/main/assets/ytdl --strip-components=2 --transform="s/python$PY_VERSION/python3/" --wildcards "*/bin/python$PY_VERSION" -xJ) \
  >(tar -C $HOME/dist --strip-components=3 --wildcards "*/lib/python$PY_VERSION/" -xJ) >/dev/null

recompile_py () {
	find . -name '*.pyc' -delete
	python$PY_VERSION -OO -m compileall -b -j$(nproc) .
	# leave only the legacy locations (*.pyc next to *.py)
	find . -name "__pycache__" -print0 | xargs -0 -- rm -rf
}

prune_stdlib () {
	local delete=(
		pydoc_data turtledemo # docs
		test unittest/test # unittests
		tkinter sqlite3 venv ensurepip # doesn't work anyway
		lib2to3 idlelib distutils multiprocessing # not used by ytdl
	)
	rm -rf "${delete[@]}"
	# ytdl tries to import this:
	rm -rf ctypes && mkdir -p ctypes
	cat >ctypes/__init__.py <<"FILE"
class cdll():
  @staticmethod
  def LoadLibrary(lib):
    raise OSError
FILE
}

(
	cd $HOME/dist
	prune_stdlib
	recompile_py
	zip -9 $GITHUB_WORKSPACE/app/src/main/assets/ytdl/python${PY_VERSION//./}.zip -R '*.pyc'
)

msg "Building mpv"
./buildall.sh -n mpv || {
	# show logfile if configure failed
	[ ! -f deps/mpv/_build/config.h ] && cat deps/mpv/_build/meson-logs/meson-log.txt
	exit 1
}

msg "Building mpv-android"
./buildall.sh -n

exit 0
