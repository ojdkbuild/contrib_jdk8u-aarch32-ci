#!/bin/bash
#
# Copyright 2018, akashche at redhat.com
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -e
set -x

# variables
export OJDK_TAG="$1"
# uncomment for standalone runs
#export OJDK_UPDATE=`echo ${OJDK_TAG} | sed 's/-/ /' | awk '{print substr($1,6)}'`
#export OJDK_BUILD=`echo ${OJDK_TAG} | sed 's/-/ /' | awk '{print substr($2,2,2)}'`
#export OJDK_MILESTONE=ojdkbuild
export OJDK_ENABLE_DEBUG_SYMBOLS=no
export OJDK_WITH_DEBUG_LEVEL=release
export OJDK_IMAGE=jdk-8u${OJDK_UPDATE}-${OJDK_MILESTONE}-linux-armhf
export OJDK_CACERTS_URL=https://github.com/ojdkbuild/lookaside_ca-certificates/raw/master/cacerts
export D="docker exec builder"

# docker
sudo docker pull ubuntu:trusty
sudo docker run \
    -id \
    --name builder \
    -w /opt \
    -v `pwd`:/host \
    ubuntu:trusty \
    bash

# sysroot dependencies
$D apt update
$D apt install -y \
    debootstrap \
    qemu-user-static

# sysroot
$D qemu-debootstrap \
    --arch=armhf \
    --verbose \
    --include=fakeroot,build-essential,libx11-dev,libxext-dev,libxrender-dev,libxtst-dev,libxt-dev,libcups2-dev,libfontconfig1-dev,libasound2-dev,libfreetype6-dev \
    --resolve-deps trusty \
    /opt/chroot \
    || true
for fi in `$D bash -c "ls /opt/chroot/var/cache/apt/archives/*.deb"` ; do
    $D dpkg-deb -R $fi /opt/sysroot
done
$D ln -s /opt/sysroot/lib/arm-linux-gnueabihf /lib/arm-linux-gnueabihf
$D ln -s /opt/sysroot/usr/lib/arm-linux-gnueabihf /usr/lib/arm-linux-gnueabihf
$D rm -rf /usr/include
$D ln -s /opt/sysroot/usr/include /usr/include

# native dependencies
$D apt install -y \
    gcc \
    g++ \
    gcc-arm-linux-gnueabihf \
    g++-arm-linux-gnueabihf \
    make \
    zip \
    unzip \
    fonts-dejavu

# boot jdk
$D wget -nv https://github.com/ojdkbuild/contrib_jdk8u-ci/releases/download/jdk8u172-b11/jdk-8u172-ojdkbuild-linux-x64.zip
$D unzip -q jdk-8u172-ojdkbuild-linux-x64.zip
$D mv jdk-8u172-ojdkbuild-linux-x64 bootjdk

# cacerts
$D wget -nv ${OJDK_CACERTS_URL} -O cacerts

# sources
$D wget -nv http://hg.openjdk.java.net/aarch32-port/jdk8u/archive/${OJDK_TAG}.tar.bz2
$D tar -xjf ${OJDK_TAG}.tar.bz2
$D rm ${OJDK_TAG}.tar.bz2
$D mv jdk8u-${OJDK_TAG} jdk8u
for repo in `echo corba hotspot jaxp jaxws jdk langtools nashorn` ; do
    $D wget -nv http://hg.openjdk.java.net/aarch32-port/jdk8u/${repo}/archive/${OJDK_TAG}.tar.bz2
    $D tar -xjf ${OJDK_TAG}.tar.bz2
    $D rm ${OJDK_TAG}.tar.bz2
    $D mv ${repo}-${OJDK_TAG} ./jdk8u/${repo}
done

# build
$D mkdir jdkbuild
$D bash -c "cd jdkbuild && \
    CC=arm-linux-gnueabihf-gcc \
    CXX=arm-linux-gnueabihf-g++ \
    bash /opt/jdk8u/configure \
    --openjdk-target=arm-linux-gnueabihf \
    --with-sys-root=/opt/sysroot/ \
    --with-jvm-variants=client \
    --enable-unlimited-crypto=yes \
    --enable-debug-symbols=${OJDK_ENABLE_DEBUG_SYMBOLS} \
    --with-debug-level=${OJDK_WITH_DEBUG_LEVEL} \
    --with-stdc++lib=static \
    --with-boot-jdk=/opt/bootjdk/ \
    --with-cacerts-file=/opt/cacerts \
    --with-freetype-include=/opt/sysroot/usr/include/freetype2/ \
    --with-freetype-lib=/opt/sysroot/usr/lib/arm-linux-gnueabihf/ \
    --with-extra-cflags='-Wno-error' \
    --with-extra-cxxflags='-Wno-error' \
    --with-milestone=${OJDK_MILESTONE} \
    --with-update-version=${OJDK_UPDATE} \
    --with-build-number=${OJDK_BUILD}"
$D bash -c "cd jdkbuild && \
    LOG=info \
    make images"

# bundle
$D mv ./jdkbuild/images/j2sdk-image ${OJDK_IMAGE}
$D rm -rf ./${OJDK_IMAGE}/demo
$D rm -rf ./${OJDK_IMAGE}/sample
$D cp -a /usr/share/fonts/truetype/dejavu/ ./${OJDK_IMAGE}/jre/lib/fonts
$D zip -qyr9 ${OJDK_IMAGE}.zip ${OJDK_IMAGE}
$D mv ${OJDK_IMAGE}.zip /host/
sha256sum ${OJDK_IMAGE}.zip > ${OJDK_IMAGE}.zip.sha256
