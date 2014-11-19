#!/bin/bash

if [ $# -ne 1 -o "$1" = "-h" -o "$1" = "--help" ]; then
    echo "Please provide the OpenAFS version number."
    echo "Example: $(basename $0) 1.4.14.1"
    exit 1
fi

openafs_version=$1

CREATEREPO_BIN=$(which createrepo 2>/dev/null)
if [ "x" = "x${CREATEREPO_BIN}" ]; then
    read -p "'createrepo' command not found. Do you want to install it? [y|N] " YN
    if [ "$YN" = "y" -o "$YN" = "Y" ]; then
        if [ -x /usr/bin/yum ]; then
            sudo yum install createrepo
        elif [ -x /usr/bin/apt-get ]; then
            sudo apt-get install createrepo
        else
            echo "unable to install createrepo. yum or apt-get are not available."
        fi
        CREATEREPO_BIN=$(which createrepo 2>/dev/null)
    fi
fi

openafs_repo_dir=/afs/.ss2k/system/pkgs/openafs

declare -a openafs_files=(dkms-openafs \
                          openafs \
                          openafs-client \
                          openafs-devel \
                          openafs-docs \
                          openafs-krb5 \
                          openafs-server);

for rhel_version in 5 6; do
    mkdir -p ${openafs_repo_dir}/${openafs_version}/rhel${rhel_version}
    cd ${openafs_repo_dir}/${openafs_version}
    [ -L ${rhel_version} ] || ln -s rhel${rhel_version} ${rhel_version}
    cd rhel${rhel_version}
    for arch in i386 x86_64; do
        mkdir -p ${arch}
        cd ${arch}
        echo "downloading files for ${openafs_version}/rhel${rhel_version}/${arch}"
        for thisfile in ${openafs_files[*]}; do
            #add fix for when i386 isn't found
            wget --quiet -O - http://dl.openafs.org/dl/${openafs_version}/rhel${rhel_version}/${arch}/ >/dev/null
            [ $? -ne 0 ] && arch=i686
            real_filename=$(wget --quiet -O - http://dl.openafs.org/dl/${openafs_version}/rhel${rhel_version}/${arch}/ \
            | grep ">${thisfile}-[0-9].*.rpm<" | head -n1 | sed -e "s/^.*>\(${thisfile}-[0-9].*.rpm\)<.*$/\1/")
            [ -f ${real_filename} ] || wget --quiet http://dl.openafs.org/dl/${openafs_version}/rhel${rhel_version}/${arch}/${real_filename}
        done
        echo "done downloading."
        if [ "x" != "x${CREATEREPO_BIN}" -a -x "${CREATEREPO_BIN}" ]; then
            echo "creating repostory..."
            ${CREATEREPO_BIN} --update ./
            echo "done."
        else
            echo "unable to run createrepo."
        fi
        cd ..
    done
    [ -L i686 ] || ln -s i386 i686
    cd ..
done

