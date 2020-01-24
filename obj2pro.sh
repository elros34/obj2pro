#!/bin/bash
# generate project file (.pro) for qtcreator from kernel build output

KERNEL_DIR="$(pwd)"
OBJECTS_DIR="$KERNEL_DIR"
CONFIG_FILE=".config"
if [ ! -f "$OBJECTS_DIR/$CONFIG_FILE" ]; then
    OBJECTS_DIR="$(ls -d ../../../out/target/product/*/obj/KERNEL_OBJ)"
    CONFIG_FILE="$OBJECTS_DIR/$CONFIG_FILE"
fi

SOURCES_LIST=""
HEADERS_LIST=""
ARCH=arm
DEFCONFIG=""

# Try to find Android defconfig
if [ -z "$DEFCONFIG" ]; then
    DEFCONFIG="$(grep -r --include "*.mk" TARGET_KERNEL_CONFIG ../../../device/ 2>/dev/null | pcregrep -o1 ".*TARGET_KERNEL_CONFIG.*= (\w+)" | head -n1)"
    if [ -n "$DEFCONFIG" ]; then
        DEFCONFIG="arch/$ARCH/configs/$DEFCONFIG"
        if [ ! -f "$DEFCONFIG" ]; then
            DEFCONFIG=""
        fi
    fi
fi
if [ -z "$DEFCONFIG" ]; then
   DEFCONFIG=".config" 
fi

# find mach-$MACHINE/inlude dir
RESULT="$(pcregrep -o1 "^(CONFIG_ARCH_[a-zA-Z0-9]+)=y$" $CONFIG_FILE | grep -v ARCH_STM32)"
for CONFIG_ARCH in $RESULT; do
    MACHINE="$(pcregrep -o1 "^machine-\\$\($CONFIG_ARCH\).*= ([a-zA-Z0-9]+)" arch/$ARCH/Makefile)" && break
done

echo "arch: $ARCH"
echo "machine: $MACHINE"
echo "defconfig: $DEFCONFIG"


INCLUDE_LIST="include arch/$ARCH/include arch/$ARCH/mach-$MACHINE/include"

append_headers() {
    if ! grep -q "$@" <<< $HEADERS_LIST ; then
        HEADERS_LIST="$HEADERS_LIST $@"
    fi
}

is_in_sources() {
    grep -q "$@" <<< $SOURCES_LIST
}

append_sources() {
    if ! is_in_sources "$@"; then
        SOURCES_LIST="$SOURCES_LIST $@"
    fi
}

# Find any #include "*.c" in used sources
extract_c() {
    if [ -f $1 ]; then
        RESULT="$(pcregrep -o1 "^#include \"(.*\.c)\"" $1)"
        if [ -n "$RESULT" ]; then
            DIR="$(dirname $1)"
            for SOURCE in $RESULT; do
                source_file=$DIR/$SOURCE
                append_sources $source_file
                # avoid circular includes
                if ! is_in_sources $source_file; then
                    extract_c $source_file # recursive
                fi 
            done
	    fi
    fi
}

objs2sources() {
    cd $OBJECTS_DIR
    OBJS="$(find * -mount -type f -name "*.o" -not -name built-in.o -not -name "*.mod.o" | sed "s|o$||")"
    cd $KERNEL_DIR

    # if .c not exist then try .S (assembler)
    for obj in $OBJS; do
        source_file=""
        if [ -f "$obj"c ]; then
            source_file="$obj"c
        elif [ -f "$obj"S ]; then
            source_file="$obj"S  
        else
            continue
        fi
        append_sources $source_file
        extract_c $source_file
    done
}

# find <*.h> in include paths
find_header_path() {
    for INCLUDE_DIR in $INCLUDE_LIST; do 
        if [ -f $INCLUDE_DIR/$1 ]; then
            append_headers $INCLUDE_DIR/$1
            return
        fi
    done
}

sources2headers() { # TODO recursive
    for SOURCE in $SOURCES_LIST; do
        if [ ! -f $SOURCE ]; then
            continue
        fi
        RESULT="$(pcregrep -o1 "^#include \"(.*\.h)\"" $SOURCE)"
        DIR="$(dirname $SOURCE)"

        if [ -n "$RESULT" ]; then
            for HEADER in $RESULT; do
                append_headers $DIR/$HEADER
            done
	    fi

        RESULT="$(pcregrep -o1 "^#include <(.*\.h)>" $SOURCE)"
        if [ -n "$RESULT" ]; then
            for HEADER in $RESULT; do
                find_header_path $HEADER
            done
	    fi
    done
}
echo "objs2sources"
objs2sources

echo "sources2headers"
sources2headers

# Format result for project (*.pro) file
HEADERS_LIST="$(echo $HEADERS_LIST | xargs -d" " -I FILE echo "  FILE" | sed -e 's|.h$|& \\|')"
SOURCES_LIST="$(echo $SOURCES_LIST | xargs -d" " -I FILE echo "  FILE" | sed -e 's|.[cS]$|& \\|')"
DEFINES_LIST="$(pcregrep -o1 "^(CONFIG_.+)=y$" $CONFIG_FILE | xargs -I CONF echo -e "  CONF \\")"
# what about CONFIG_*=m?

echo "create kernel.pro"
touch .kernel.pro.new

# To find correct headers in kernel tree not in system
echo -e "INCLUDEPATH += \\" > .kernel.pro.new
echo -e "  \$\$PWD/include \\" >> .kernel.pro.new
echo -e "  \$\$PWD/arch/$ARCH/include \\" >> .kernel.pro.new
echo -e "  \$\$PWD/arch/$ARCH/mach-$MACHINE/include" >> .kernel.pro.new

echo -e "\nOTHER_FILES += \\" >> .kernel.pro.new
if [ -n "$DEFCONFIG" ] && [ $DEFCONFIG != $CONFIG_FILE ]; then
    echo -e "  $DEFCONFIG \\" >> .kernel.pro.new
fi
echo -e "  $CONFIG_FILE" >> .kernel.pro.new

echo -e "\nDEFINES += \\" >> .kernel.pro.new
echo -e "  __KERNEL__ \\" >> .kernel.pro.new
echo -e "$DEFINES_LIST" >> .kernel.pro.new


echo -e "\n\n# *.h files" >> .kernel.pro.new
echo -e "HEADERS += \\" >> .kernel.pro.new
echo -e "$HEADERS_LIST" >> .kernel.pro.new
echo -e "\n" >> .kernel.pro.new

echo -e "\n\n# *.c files" >> .kernel.pro.new
echo -e "SOURCES += \\" >> .kernel.pro.new
echo -e "$SOURCES_LIST" >> .kernel.pro.new

mv .kernel.pro.new kernel.pro

times
