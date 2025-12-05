# verilator-bin
Binary build of Verilator for various platforms

## Prerequisites

### Ubuntu/Debian
```bash
sudo apt-get install -y cmake build-essential autoconf flex bison \
    help2man python3 python3-venv git
```

### CentOS/RHEL
```bash
sudo yum install -y cmake gcc gcc-c++ autoconf flex bison \
    help2man python3 git
```

**Note:** GMP and MPFR are automatically downloaded and built by the CMake build system.

## Building

### Build with tagged releases (default branches):
```bash
mkdir build && cd build
cmake .. -DUSE_LATEST_BRANCH=OFF
make -j$(nproc)
```

### Build with latest main/master branches:
```bash
mkdir build && cd build
cmake .. -DUSE_LATEST_BRANCH=ON
make -j$(nproc)
```

### Build with specific tags:
```bash
mkdir build && cd build
cmake .. -DVERILATOR_TAG=v5.030 -DBITWUZLA_TAG=0.6.0
make -j$(nproc)
```

The built binaries will be in `build/install/`
