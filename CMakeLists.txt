cmake_minimum_required(VERSION 3.15)
project(verilator-bin)

include(ExternalProject)
include(ProcessorCount)
ProcessorCount(NPROC)

# Options to control build behavior
option(USE_LATEST_BRANCH "Use latest main branch instead of tagged release" ON)
set(VERILATOR_TAG "" CACHE STRING "Specific Verilator tag to use (overrides USE_LATEST_BRANCH)")
set(BITWUZLA_TAG "" CACHE STRING "Specific Bitwuzla tag to use (overrides USE_LATEST_BRANCH)")

# Set install prefix if not specified
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${CMAKE_BINARY_DIR}/install" CACHE PATH "Installation directory" FORCE)
endif()

# Determine Bitwuzla version/branch
if(BITWUZLA_TAG)
  set(BITWUZLA_GIT_TAG ${BITWUZLA_TAG})
elseif(USE_LATEST_BRANCH)
  set(BITWUZLA_GIT_TAG "main")
else()
  # Will be set to latest release tag via environment variable or default
  set(BITWUZLA_GIT_TAG "0.6.0")
endif()

# Determine Verilator version/branch
if(VERILATOR_TAG)
  set(VERILATOR_GIT_TAG ${VERILATOR_TAG})
elseif(USE_LATEST_BRANCH)
  set(VERILATOR_GIT_TAG "master")
else()
  # Will be set to latest release tag via environment variable or default
  set(VERILATOR_GIT_TAG "v5.030")
endif()

message(STATUS "Building with Bitwuzla: ${BITWUZLA_GIT_TAG}")
message(STATUS "Building with Verilator: ${VERILATOR_GIT_TAG}")

# Create a Python virtual environment for meson/ninja
ExternalProject_Add(python-venv
  DOWNLOAD_COMMAND ""
  CONFIGURE_COMMAND python3 -m venv <BINARY_DIR>/venv
  BUILD_COMMAND <BINARY_DIR>/venv/bin/pip install meson ninja
  INSTALL_COMMAND ""
  BUILD_IN_SOURCE 1
)

# Build GMP (required by MPFR and Bitwuzla)
# Use local cached copy to avoid network issues
# Build both static and shared libraries so meson can find them
ExternalProject_Add(gmp
  URL ${CMAKE_SOURCE_DIR}/deps/gmp-6.3.0.tar.xz
  URL_HASH SHA256=a3c2b80201b89e68616f4ad30bc66aee4927c3ce50e33929ca819d5c43538898
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE
  CONFIGURE_COMMAND <SOURCE_DIR>/configure --prefix=${CMAKE_INSTALL_PREFIX} --enable-cxx
  BUILD_COMMAND make -j${NPROC}
  INSTALL_COMMAND make install
  BUILD_IN_SOURCE 1
)

# Build MPFR (required by Bitwuzla, depends on GMP)
# Use local cached copy to avoid network issues
# Build both static and shared libraries so meson can find them
ExternalProject_Add(mpfr
  DEPENDS gmp
  URL ${CMAKE_SOURCE_DIR}/deps/mpfr-4.2.2.tar.xz
  URL_HASH SHA256=b67ba0383ef7e8a8563734e2e889ef5ec3c3b898a01d00fa0a6869ad81c6ce01
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE
  CONFIGURE_COMMAND <SOURCE_DIR>/configure --prefix=${CMAKE_INSTALL_PREFIX} --with-gmp=${CMAKE_INSTALL_PREFIX}
  BUILD_COMMAND make -j${NPROC}
  INSTALL_COMMAND make install
  BUILD_IN_SOURCE 1
)

# Build Bitwuzla
# Use meson directly with --wrap-mode=nofallback to prevent fallback to wrap for GMP/MPFR
# Pass pkg-config-path and native-file for proper library detection on macOS
ExternalProject_Add(bitwuzla
  DEPENDS python-venv gmp mpfr
  GIT_REPOSITORY https://github.com/bitwuzla/bitwuzla.git
  GIT_TAG ${BITWUZLA_GIT_TAG}
  CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env 
    PATH=${CMAKE_BINARY_DIR}/python-venv-prefix/venv/bin:$ENV{PATH}
    PKG_CONFIG_PATH=${CMAKE_INSTALL_PREFIX}/lib/pkgconfig:$ENV{PKG_CONFIG_PATH}
    LD_LIBRARY_PATH=${CMAKE_INSTALL_PREFIX}/lib:$ENV{LD_LIBRARY_PATH}
    DYLD_LIBRARY_PATH=${CMAKE_INSTALL_PREFIX}/lib:$ENV{DYLD_LIBRARY_PATH}
    LIBRARY_PATH=${CMAKE_INSTALL_PREFIX}/lib:$ENV{LIBRARY_PATH}
    meson setup <SOURCE_DIR>/build <SOURCE_DIR> 
      --prefix=${CMAKE_INSTALL_PREFIX} 
      -Dfpexp=false 
      --wrap-mode=nofallback
      --default-library=shared
      --pkg-config-path=${CMAKE_INSTALL_PREFIX}/lib/pkgconfig
      -Dc_args=-I${CMAKE_INSTALL_PREFIX}/include
      -Dcpp_args=-I${CMAKE_INSTALL_PREFIX}/include
      -Dc_link_args=-L${CMAKE_INSTALL_PREFIX}/lib
      -Dcpp_link_args=-L${CMAKE_INSTALL_PREFIX}/lib
  BUILD_COMMAND ${CMAKE_COMMAND} -E chdir <SOURCE_DIR>/build ${CMAKE_COMMAND} -E env 
    PATH=${CMAKE_BINARY_DIR}/python-venv-prefix/venv/bin:$ENV{PATH}
    LD_LIBRARY_PATH=${CMAKE_INSTALL_PREFIX}/lib:$ENV{LD_LIBRARY_PATH}
    DYLD_LIBRARY_PATH=${CMAKE_INSTALL_PREFIX}/lib:$ENV{DYLD_LIBRARY_PATH}
    meson compile
  INSTALL_COMMAND ${CMAKE_COMMAND} -E chdir <SOURCE_DIR>/build ${CMAKE_COMMAND} -E env 
    PATH=${CMAKE_BINARY_DIR}/python-venv-prefix/venv/bin:$ENV{PATH}
    LD_LIBRARY_PATH=${CMAKE_INSTALL_PREFIX}/lib:$ENV{LD_LIBRARY_PATH}
    DYLD_LIBRARY_PATH=${CMAKE_INSTALL_PREFIX}/lib:$ENV{DYLD_LIBRARY_PATH}
    meson install
  BUILD_IN_SOURCE 1
)

# Build Verilator
ExternalProject_Add(verilator
  DEPENDS bitwuzla
  GIT_REPOSITORY https://github.com/verilator/verilator.git
  GIT_TAG ${VERILATOR_GIT_TAG}
  CONFIGURE_COMMAND autoconf COMMAND <SOURCE_DIR>/configure --prefix=${CMAKE_INSTALL_PREFIX} --with-solver=bitwuzla
  BUILD_COMMAND make -j${NPROC}
  INSTALL_COMMAND make install
  BUILD_IN_SOURCE 1
)

# Fetch and install UVM
ExternalProject_Add(uvm
  URL https://www.accellera.org/images/downloads/standards/uvm/Accellera-1800.2-2017-1.0.tar.gz
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE
  CONFIGURE_COMMAND ""
  BUILD_COMMAND ""
  INSTALL_COMMAND ${CMAKE_COMMAND} -E make_directory ${CMAKE_INSTALL_PREFIX}/share/uvm
    COMMAND ${CMAKE_COMMAND} -E copy_directory <SOURCE_DIR>/src ${CMAKE_INSTALL_PREFIX}/share/uvm/src
)

# Post-install cleanup and modifications
ExternalProject_Add(post-install
  DEPENDS verilator uvm
  DOWNLOAD_COMMAND ""
  CONFIGURE_COMMAND ""
  BUILD_COMMAND ""
  INSTALL_COMMAND 
    ${CMAKE_COMMAND} -E echo "Running post-install cleanup..."
    COMMAND bash -c "test -f ${CMAKE_INSTALL_PREFIX}/bin/verilator_bin && strip ${CMAKE_INSTALL_PREFIX}/bin/* 2>/dev/null || true"
    COMMAND bash -c "test -d ${CMAKE_INSTALL_PREFIX}/share/verilator/bin && strip ${CMAKE_INSTALL_PREFIX}/share/verilator/bin/* 2>/dev/null || true"
    COMMAND ${CMAKE_COMMAND} -E rm -rf ${CMAKE_INSTALL_PREFIX}/lib
    COMMAND bash -c "rm -f ${CMAKE_INSTALL_PREFIX}/share/verilator/bin/*_dbg 2>/dev/null || true"
    COMMAND bash -c "test -f ${CMAKE_INSTALL_PREFIX}/share/verilator/include/verilated.mk && sed -i 's%PYTHON3 =.*$%PYTHON3 = python3%g' ${CMAKE_INSTALL_PREFIX}/share/verilator/include/verilated.mk || true"
)
