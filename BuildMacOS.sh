#!/bin/bash
#
# This script can download and compile dependencies, compile PrusauSlicer
# and optional build a .tgz and an appimage.
#
# Original script from SuperSclier by supermerill https://github.com/supermerill/SuperSlicer
#
# Change log:
#
# 20 Nov 2023, wschadow, branding and minor changes
# 01 Jan 2024, wschadow, debranding for the Prusa version, added build options
#

export ROOT=`pwd`
export NCORES=`sysctl -n hw.ncpu`


OS_FOUND=$( command -v uname)

case $( "${OS_FOUND}" | tr '[:upper:]' '[:lower:]') in
  linux*)
    TARGET_OS="linux"
   ;;
  msys*|cygwin*|mingw*)
    # or possible 'bash on windows'
    TARGET_OS='windows'
   ;;
  nt|win*)
    TARGET_OS='windows'
    ;;
  darwin)
    TARGET_OS='macos'
    ;;
  *)
    TARGET_OS='unknown'
    ;;
esac

# check operating system
echo
if [ $TARGET_OS == "macos" ]; then
    if [ $(uname -m) == "x86_64" ]; then
        echo -e "$(tput setaf 2)macOS x86_64 found$(tput sgr0)\n"
        Processor="64"
    elif [[ $(uname -m) == "i386" || $(uname -m) == "i686" ]]; then
        echo "$(tput setaf 2)macOS arm64 found$(tput sgr0)\n"
        Processor="64"
    else
        echo "$(tput setaf 1)Unsupported OS: macOS $(uname -m)"
        exit -1
    fi
else
    echo -e "$(tput setaf 1)This script doesn't support your Operating system!"
    echo -e "Please use Linux 64-bit or Windows 10 64-bit with Linux subsystem / git-bash.$(tput sgr0)\n"
#    exit -1
fi

# Check if CMake is installed
export CMAKE_INSTALLED=`which cmake`
if [[ -z "$CMAKE_INSTALLED" ]]
then
    echo "Can't find CMake. Either is not installed or not in the PATH. Aborting!"
    exit -1
fi

while getopts ":idaxbhcsw" opt; do
  case ${opt} in
    i )
        BUILD_IMAGE="1"
        ;;
    d )
        BUILD_DEPS="1"
        ;;        
    a )
        export BUILD_ARCH="arm64"
        ;;
    x )
        export BUILD_ARCH="x86_64"
        ;;
    b )
        BUILD_DEBUG="1"
        ;;
    s )
        BUILD_PRUSASLICER="1"
        ;;
    c)
        BUILD_XCODE="1"
        ;;
    w )
	    BUILD_WIPE="1"
	;;        
    h ) echo "Usage: ./BuildMacOS.sh  [-h][-w][-d][-a][-x][-b][-c][-s][-i]"
        echo "   -h: this message"    
	    echo "   -w: wipe build directories bfore building"        
        echo "   -d: build dependencies"
        echo "   -a: Build for arm64 (Apple Silicon)"
        echo "   -x: Build for x86_64 (Intel)"
        echo "   -b: Build with debug symbols"
        echo "   -c: Build for XCode"
        echo "   -s: build PrusaSlicer"        
        echo "   -i: Generate DMG image (optional)\n"        
        exit 0
        ;;
  esac
done

if [ $OPTIND -eq 1 ]
then
    echo "Usage: ./BuildLinux.sh [-h][-w][-d][-a][-x][-b][-c][-s][-i]"
    echo "   -h: this message"   
	echo "   -w: wipe build directories bfore building"         
    echo "   -d: build dependencies"
    echo "   -a: Build for arm64 (Apple Silicon)"
    echo "   -x: Build for x86_64 (Intel)"
    echo "   -b: Build with debug symbols"
    echo "   -c: Build for XCode"
    echo "   -s: build PrusaSlicer"    
    echo -e "   -i: Generate DMG image (optional)\n"        
    exit 0
fi

export LIBRARY_PATH=$LIBRARY_PATH:$(brew --prefix zstd)/lib/

if [[ -n "$BUILD_DEPS" ]]
then
    if [[ -n $BUILD_WIPE ]]
    then
       rm -fr deps/build
    fi
    # mkdir in deps
    if [ ! -d "deps/build" ]
    then
    mkdir deps/build
    fi
    echo -e " \n[1/9] Configuring dependencies ... \n"
    BUILD_ARGS=""
    if [[ -n "$BUILD_ARCH" ]]
    then
        BUILD_ARGS="${BUILD_ARGS}  -DCMAKE_OSX_ARCHITECTURES:STRING=${BUILD_ARCH}"
    fi
    if [[ -n "$BUILD_DEBUG" ]]
    then
        BUILD_ARGS="${BUILD_ARGS} -DCMAKE_BUILD_TYPE=Debug"
    fi
    # cmake deps
    echo "Cmake command: cmake .. -DCMAKE_OSX_DEPLOYMENT_TARGET=\"10.14\" ${BUILD_ARCH} "
    pushd deps/build > /dev/null
    cmake .. -DCMAKE_OSX_DEPLOYMENT_TARGET="10.14" $BUILD_ARGS 

    echo -e "\n... done\n"

    echo -e "[2/9] Building dependencies ...\n"

    # make deps
    make -j$NCORES

    echo -e "\n... done\n"

    echo -e "[3/9] Renaming wxscintilla library ...\n"

    # rename wxscintilla
    pushd destdir/usr/local/lib
    cp libwxscintilla-3.1.a libwx_osx_cocoau_scintilla-3.1.a

    popd > /dev/null
    echo -e "\n... done\n"

    echo -e "[4/9] Cleaning dependencies...\n"

    # clean deps
    rm -rf dep_*
    popd > /dev/null

    echo -e "\n... done\n"
fi

if [[ -n "$BUILD_PRUSASLICER" ]]
then
    echo -e "[5/9] Configuring PrusaSlicer ...\n"

    if [[ -n $BUILD_WIPE ]]
    then
       rm -fr build
    fi

    # mkdir build
    if [ ! -d "build" ]
    then
	mkdir build
    fi

    BUILD_ARGS=""
    if [[ -n "$BUILD_ARCH" ]]
    then
        BUILD_ARGS="${BUILD_ARGS} -DCMAKE_OSX_ARCHITECTURES=${BUILD_ARCH}"
    fi
    if [[ -n "$BUILD_DEBUG" ]]
    then
        BUILD_ARGS="-DCMAKE_BUILD_TYPE=Debug ${BUILD_ARGS}"
    fi
    if [[ -n "$BUILD_XCODE" ]]
    then
        BUILD_ARGS="-GXcode ${BUILD_ARGS}"
    fi
    # cmake
    pushd build > /dev/null
    cmake .. -DCMAKE_PREFIX_PATH="$PWD/../deps/build/destdir/usr/local" -DCMAKE_OSX_DEPLOYMENT_TARGET="10.14" -DSLIC3R_STATIC=1 ${BUILD_ARGS}
    echo -e "\n... done"

    # make Slic3r
    if [[ -z "$BUILD_XCODE" ]]
    then
        echo -e "\n[6/9] Building PrusaSlicer ...\n"
        make -j$NCORES
        echo -e "\n... done"
    fi

    echo -e "\n[7/9] Generating language files ...\n"
    #make .mo
    make gettext_po_to_mo
    
    popd  > /dev/null
    echo -e "\n... done"

    # Give proper permissions to script
    chmod 755 $ROOT/build/src/BuildMacOSImage.sh

    pushd build  > /dev/null
    $ROOT/build/src/BuildMacOSImage.sh -a 
    popd  > /dev/null  
fi

if [[ -n "$BUILD_IMAGE" ]]
then
    # Give proper permissions to script
    chmod 755 $ROOT/build/src/BuildMacOSImage.sh
    pushd build  > /dev/null
    $ROOT/build/src/BuildMacOSImage.sh -i
    popd  > /dev/null
fi
