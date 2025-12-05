#!/bin/sh -x

root=$(pwd)

#********************************************************************
#* Install required packages
#********************************************************************
if test $(uname -s) = "Linux"; then
    yum update -y
    yum install -y glibc-static wget flex bison jq help2man \
        cmake3 autoconf make gcc gcc-c++ git

    if test -z $image; then
        image=linux
    fi
    export PATH=/opt/python/cp312-cp312/bin:$PATH
    
    # Install meson and ninja for bitwuzla build
    pip3 install meson ninja
    
    # Create cmake symlink if cmake3 exists
    if test -f /usr/bin/cmake3 && test ! -f /usr/bin/cmake; then
        ln -s /usr/bin/cmake3 /usr/bin/cmake
    fi
    
    rls_plat=${image}
elif test $(uname -s) = "Darwin"; then
    # macOS - dependencies installed via brew in CI
    if test -z $image; then
        image=macos-$(uname -m)
    fi
    
    # Install meson and ninja for bitwuzla build
    pip3 install meson ninja --break-system-packages || pip3 install meson ninja
    
    # Set flag to remove pregen files on macOS to avoid flex compatibility issues
    REMOVE_PREGEN=1
    
    rls_plat=${image}
elif test $(uname -s) = "Windows"; then
    rls_plat="windows-x64"
fi

#********************************************************************
#* Validate environment variables
#********************************************************************
if test -z $vlt_latest_rls; then
  echo "vlt_latest_rls not set"
  env
  exit 1
fi

if test -z $bwz_latest_rls; then
  echo "bwz_latest_rls not set"
  env
  exit 1
fi

#********************************************************************
#* Calculate version information
#********************************************************************
if test -z ${rls_version}; then
    vlt_version=$(echo $vlt_latest_rls | sed -e 's/^v//')
    rls_version=${vlt_version}

    if test "x${BUILD_NUM}" != "x"; then
        rls_version="${rls_version}.${BUILD_NUM}"
    fi
fi

#********************************************************************
#* Build using CMake
#********************************************************************
cd ${root}

# Create build directory
rm -rf build
mkdir -p build
cd build

# Configure CMake with version information from GitHub workflow
# When vlt_latest_rls is "master", use USE_LATEST_BRANCH=ON for top-of-trunk builds
if test "${vlt_latest_rls}" = "master"; then
  cmake .. \
    -DUSE_LATEST_BRANCH=ON \
    -DBITWUZLA_TAG=${bwz_latest_rls} \
    -DCMAKE_INSTALL_PREFIX=${root}/release/verilator
else
  cmake .. \
    -DUSE_LATEST_BRANCH=OFF \
    -DVERILATOR_TAG=${vlt_latest_rls} \
    -DBITWUZLA_TAG=${bwz_latest_rls} \
    -DCMAKE_INSTALL_PREFIX=${root}/release/verilator
fi

if test $? -ne 0; then exit 1; fi

# On macOS, remove pregen lex files to force regeneration with homebrew flex
# This avoids compatibility issues with the system FlexLexer.h
if test "x${REMOVE_PREGEN}" = "x1"; then
    echo "Removing pregen lex files for macOS compatibility..."
    find . -name "*_pregen*" -delete 2>/dev/null || true
fi

# Build
make -j$(nproc)
if test $? -ne 0; then exit 1; fi

#********************************************************************
#* Create release tarball
#********************************************************************
cd ${root}/release

tar czf verilator-${rls_plat}-${rls_version}.tar.gz verilator
if test $? -ne 0; then exit 1; fi

echo "Build complete: verilator-${rls_plat}-${rls_version}.tar.gz"

