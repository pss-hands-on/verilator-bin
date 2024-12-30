#!/bin/sh -x

root=$(pwd)
PATH_SAV=${PATH}

yum update -y
yum install -y glibc-static

export PATH=/opt/python/cp312-cp312/bin:$PATH
if test ! -d py; then
    python3 -m venv py
    if test $? -ne 0; then exit 1; fi

    ./py/bin/pip install meson ninja
    if test $? -ne 0; then exit 1; fi
fi


vlt_latest_rls=$(curl -s -L \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  https://api.github.com/repos/verilator/verilator/git/refs/tags | \
  jq ".[].ref" | sed -e's%refs/tags/%%' -e 's/\"//g'| sort | tail -n 1)
if test $? -ne 0; then exit 1; fi

bwz_latest_rls=$(curl -s -L \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  https://api.github.com/repos/bitwuzla/bitwuzla/releases/latest | \
  jq ".tag_name" | sed -e 's/\"//g')
if test $? -ne 0; then exit 1; fi

if test ! -f ${vlt_latest_rls}.tar.gz; then
    wget https://github.com/verilator/verilator/archive/refs/tags/${vlt_latest_rls}.tar.gz
    if test $? -ne 0; then exit 1; fi
fi

if test ! -f ${bwz_latest_rls}.tar.gz; then
    wget https://github.com/bitwuzla/bitwuzla/archive/refs/tags/${bwz_latest_rls}.tar.gz
    if test $? -ne 0; then exit 1; fi
fi


vlt_version=$(echo $vlt_latest_rls | sed -e 's/^v//')
rls_version=${vlt_version}

if test "x${BUILD_NUM}" != "x"; then
    rls_version="${rls_version}.${BUILD_NUM}"
fi

release_dir="${root}/release/verilator-${rls_version}"
rm -rf ${release_dir}
mkdir -p ${release_dir}

#********************************************************************
#* Build Bitwuzla
#********************************************************************
cd ${root}
bwz_version=${bwz_latest_rls}
if test -d bitwuzla-${bwz_version}; then
    rm -rf bitwuzla-${bwz_version}
fi

tar xvzf ${bwz_latest_rls}.tar.gz
if test $? -ne 0; then exit 1; fi

export PATH=${root}/py/bin:${PATH}

cd bitwuzla-${bwz_version}
./configure.py --prefix ${release_dir}
if test $? -ne 0; then exit 1; fi

cd build

meson compile
if test $? -ne 0; then exit 1; fi

meson install
if test $? -ne 0; then exit 1; fi

PATH=${PATH_SAV}

#********************************************************************
#* Build Verilator
#********************************************************************
cd ${root}

if test -d verilator-${vlt_version}; then
    rm -rf verilator-${vlt_version}
fi

tar xvzf ${vlt_latest_rls}.tar.gz
if test $? -ne 0; then exit 1; fi

mv verilator-${vlt_version} verilator-src

cd verilator-src
autoconf
if test $? -ne 0; then exit 1; fi
./configure --prefix=${release_dir} --with-solver='bitwuzla'
if test $? -ne 0; then exit 1; fi

make -j$(nproc)
if test $? -ne 0; then exit 1; fi
make install
if test $? -ne 0; then exit 1; fi

#********************************************************************
#* Clean-up
#********************************************************************
cd ${release_dir}/bin
strip *
cd ${release_dir}/share/verilator/bin
strip *
rm -rf ${release_dir}/lib
rm -f ${release_dir}/share/verilator/bin/*_dbg

#********************************************************************
#* Clean-up
#********************************************************************
cd ${root}/release


#tar czf verilator-linux-${vlt_version}.tar.gz verilator
tar czf verilator-ubuntu-x64-${rls_version}.tar.gz verilator-${rls_version}

