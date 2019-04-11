#!/bin/bash
#
#  Build script for debian package
#
#  MIT License
#  Copyright (c) 2019 Jean Prunneaux
#

# go into current directory
cd "$(dirname "$0")"
if [ $? != 0 ] ; then
	echo "ERROR: cannot go into current directory"
	exit 1
fi

# save current directory path
current_directory=$(pwd)

build_directory=archives/build

# test if sources are there
if ! [ -d src ] ; then
	echo "ERROR: you must put your sources in the src directory!"
	exit 1
fi


#
#  Functions
#

# Print help
# Usage: print_help
print_help() {
	echo "Usage: $0 [OPTIONS]"
	echo "Options:"
	echo "   -v, --version VERSION  Specify a version"
	echo "   -f, --force            Do not print confimation before build"
	echo "   -h, --help             Print this help"
}


# Get version from latest git tag
# Usage: $(get_version)
#        (to keep context)
get_version() {
	cd src || return 1

	local version
	version=$(git describe --tags)

	# remove 'v'
	[ "${version:0:1}" == v ] && version=${version:1}

	echo -n $version
}


# Fix all directory permissions to 755
# Usage: set_permissions /path/to/dir
fix_permissions() {
	local d=$1

	while [ "$d" != . ] ; do
		chmod 755 "$d"
		d=$(dirname "$d")
	done
}


# Clean build directory
# Usage: clean_build
clean_build() {
	[ -d "$current_directory/$build_directory" ] || return 0
	sudo rm -rf "$current_directory/$build_directory"
}


# Quit and clean build directory
# Usage: quit EXITCODE
quit() {
	clean_build &> /dev/null
	exit $1
}


#
#  Main program
#

# get options
while [ $# -gt 0 ] ; do
	case $1 in
		-v|--version)
			if [ -z "$2" ] ; then
				print_help
				exit 1
			fi
			version=$2
			shift
			;;
		-f|--force)
			force_mode=true
			;;
		-h|--help)
			print_help
			exit
			;;
		*)
			break
			;;
	esac
	shift
done

# test config files
for f in build.conf package/DEBIAN/control ; do
	if ! [ -f debconf/"$f" ] ; then
		echo "ERROR: $f does not exists. Please verify your 'debconf' folder."
		exit 1
	fi
done

# load build config file
if ! source debconf/build.conf ; then
	echo "There are errors inside your build.conf"
	exit 1
fi

# test name
if [ -z "$name" ] ; then
	echo "You must set a name for your package"
	exit 1
fi

# test path
if [ -z "$path" ] ; then
	echo "You must set a path where you sources are going!"
	exit 1
fi

if [ -f "$current_directory"/debconf/prebuild.sh ] ; then
	echo "Run prebuild..."

	if ! cd src ; then
		echo "... Failed to go in sources directory!"
		exit 7
	fi

	source "$current_directory"/debconf/prebuild.sh
	if [ $? != 0 ] ; then
		echo "... Failed!"
		exit 7
	fi

	# return in current directory
	if ! cd "$current_directory" ; then
		echo "... Failed to go in current directory!"
		exit 7
	fi

	echo
fi

# prompt to choose version
if [ -z "$version" ] ; then
	# try to get version from latest git tag
	version=$(get_version 2> /dev/null)

	echo -n "Choose version: "

	[ -n "$version" ] && echo -n "[$version] "

	read version_user
	if [ -n "$version_user" ] ; then
		version=$version_user
	else
		# no specified version: quit
		[ -z "$version" ] && exit 1
	fi
	echo
fi

# set package name
package=$(echo "$name" | sed "s/{version}/$version/").deb

if [ "$force_mode" != true ] ; then
	echo "You are about to build $package"
	echo -n "Continue (y/N)? "
	read confirm
	[ "$confirm" != y ] && exit
fi

# clean and copy package files
echo
echo "Clean & prepare build environment..."
mkdir -p archives && clean_build && \
cp -rp debconf/package "$build_directory"
if [ $? != 0 ] ; then
	echo "... Failed! Please check your access rights."
	exit 3
fi

echo "Set version number..."
sed -i "s/^Version: .*$/Version: $version/" "$build_directory"/DEBIAN/control
if [ $? != 0 ] ; then
	echo "... Failed! Please check your access rights."
	quit 4
fi

echo "Copy sources..."

install_path=$build_directory/$path

mkdir -p "$(dirname "$install_path")" && \
cp -rp src "$install_path"
if [ $? != 0 ] ; then
	echo "... Failed! Please check your access rights."
	quit 5
fi

echo "Clean unnecessary files..."

if ! cd "$install_path" ; then
	echo "... Failed to go inside path directory!"
	quit 6
fi

for f in "${clean[@]}" ; do

	if [ "${f:0:1}" == '/' ] ; then
		files=(".$f")
	else
		files=($(find . -name "$f"))
	fi

	if [ ${#files[@]} -gt 0 ] ; then
		echo "Delete ${files[@]}..."
		if ! rm -rf "${files[@]}" ; then
			echo '... Failed!'
			quit 6
		fi
	fi
done

echo
echo "Set root privileges..."

# go into build directory
cd "$current_directory/$build_directory"
if [ $? != 0 ] ; then
	echo "... Failed to go into build directory!"
	quit 8
fi

# fix directories permissions & set root privileges
fix_permissions ".$path" && sudo chown -R root:root .
if [ $? != 0 ] ; then
	echo "... Failed!"
	quit 8
fi

# postbuild
if [ -f "$current_directory"/debconf/postbuild.sh ] ; then
	echo
	echo "Run postbuild..."

	source "$current_directory"/debconf/postbuild.sh
	if [ $? != 0 ] ; then
		echo "... Failed!"
		quit 9
	fi
fi

echo
echo "Generate deb package..."

# go into archives directory
cd "$current_directory"/archives
if [ $? != 0 ] ; then
	echo "... Failed to go into archives directory!"
	quit 10
fi

# generate deb file + give ownership to current user
sudo dpkg-deb --build build "$package" && \
sudo chown "$(whoami)" "$package"
if [ $? != 0 ] ; then
	echo "... Failed!"
	quit 10
fi

echo
echo "Create version directory..."

# create package version directory
mkdir -p "$version" && mv "$package" "$version"
if [ $? != 0 ] ; then
	echo "... Failed!"
	quit 11
fi

echo "Clean files..."
clean_build

echo
echo "Generate checksum..."

if cd "$version" ; then
	# generate checksum
	cs=$(shasum -a 256 "$package")

	if [ -n "$cs" ] ; then
		# write checksum in file
		echo "$cs" > sha256sum.txt
		if [ $? != 0 ] ; then
			echo "... Failed to write inside checksum file!"
		fi
	else
		echo "... Failed to generate checksum!"
	fi
else
		echo "... Failed to go into version directory!"
fi

echo
echo "Package is ready!"
