GCC_VERSION=$(gcc -dM -E -  < /dev/null | grep -w __GNUC__ | awk '{print $NF;}')
if [ -z "$GCC_VERSION" ]; then
  echo -e "gcc not found, please install gcc first\n" 1>&2
  exit 2
fi

tmp_src_filename=fast_check_bits.c
cat <<EOF > $tmp_src_filename
#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>
int main()
{
	printf("%d\n", (int)sizeof(void*));
	printf("%d\n", (int)sizeof(off_t));
#ifdef __GLIBC_MINOR__
	printf("%d\n", __GLIBC_MINOR__);
#endif
	return 0;
}
EOF

gcc -D_FILE_OFFSET_BITS=64 -o a.out $tmp_src_filename
output=$(./a.out)
if [ $? -ne 0 ]; then
  echo -e "Can't find a.out program\n" 1>&2
  exit 2
fi

if [ -f /bin/expr ]; then
  EXPR=/bin/expr
elif [ -f /usr/bin/expr ]; then
  EXPR=/usr/bin/expr
else
  EXPR=$(which expr)
  if [ $? -ne 0 ]; then
    echo -e "Can't find expr program\n" 1>&2
    exit 2
  fi
fi

count=0
int_bytes=4
off_bytes=8
glibc_minor=0
LIB_VERSION=lib64

for col in $output; do
    if [ $count -eq 0 ]; then
        int_bytes=$col
    elif [ $count -eq 1 ]; then
        off_bytes=$col
    else
        glibc_minor=$col
    fi

    count=$($EXPR $count + 1)
done

/bin/rm -f a.out $tmp_src_filename

uname=$(uname)
TARGET_PREFIX=$DESTDIR/usr
if [ "$int_bytes" -eq 8 ]; then
  OS_BITS=64
  if [ $uname = 'Linux' ]; then
    osname=$(cat /etc/os-release | grep -w NAME | awk -F '=' '{print $2;}' | \
            awk -F '"' '{if (NF==3) {print $2} else {print $1}}' | awk '{print $1}')
    if [ $osname = 'Ubuntu' -o $osname = 'Debian' ]; then
      LIB_VERSION=lib
    else
      LIB_VERSION=lib64
    fi
  else
    LIB_VERSION=lib
  fi
else
  OS_BITS=32
  LIB_VERSION=lib
fi

if [ "$off_bytes" -eq 8 ]; then
  OFF_BITS=64
else
  OFF_BITS=32
fi

DEBUG_FLAG=0

export CC=gcc
CFLAGS='-Wall'
if [ -n "$GCC_VERSION" ] && [ $GCC_VERSION -ge 7 ]; then
  CFLAGS="$CFLAGS -Wformat-truncation=0 -Wformat-overflow=0"
fi
CFLAGS="$CFLAGS -D_FILE_OFFSET_BITS=64 -D_GNU_SOURCE"
if [ "$DEBUG_FLAG" = "1" ]; then
  CFLAGS="$CFLAGS -g -DDEBUG_FLAG"
else
  CFLAGS="$CFLAGS -g -O3"
fi

INCS=''
LIBS='-lm -ldl'
if [ -f /usr/include/curl/curl.h ] || [ -f /usr/local/include/curl/curl.h ]; then
  CFLAGS="$CFLAGS -DUSE_LIBCURL"
  LIBS="$LIBS -lcurl"
fi

uname=`uname`

HAVE_VMMETER_H=0
HAVE_USER_H=0
if [ "$uname" = "Linux" ]; then
  OS_NAME=OS_LINUX

  major_version=$(uname -r | awk -F . '{print $1;}')
  minor_version=$(uname -r | awk -F . '{print $2;}')
  if [ $major_version -eq 5 ] && [ $minor_version -ge 14 ]; then
    out=$(grep -F IORING_OP_SEND_ZC /usr/include/liburing/io_uring.h)
    if [ -z $out ]; then
      IOEVENT_USE=IOEVENT_USE_EPOLL
    else
      IOEVENT_USE=IOEVENT_USE_URING
    fi
  elif [ $major_version -gt 5 ]; then
    IOEVENT_USE=IOEVENT_USE_URING
  else
    IOEVENT_USE=IOEVENT_USE_EPOLL
  fi

  if [ $glibc_minor -lt 17 ]; then
    LIBS="$LIBS -lrt"
  fi
elif [ "$uname" = "FreeBSD" ] || [ "$uname" = "Darwin" ]; then
  OS_NAME=OS_FREEBSD 
  IOEVENT_USE=IOEVENT_USE_KQUEUE
  if [ "$uname" = "Darwin" ]; then
    CFLAGS="$CFLAGS -DDARWIN"
    TARGET_PREFIX=$TARGET_PREFIX/local
  else
    INCS="$INCS -I/usr/local/include"
    LIBS="$LIBS -L/usr/local/lib"
  fi

  if [ -f /usr/include/sys/vmmeter.h ]; then
     HAVE_VMMETER_H=1
  fi

  if [ -f /usr/include/sys/user.h ]; then
     HAVE_USER_H=1
  fi
elif [ "$uname" = "SunOS" ]; then
  OS_NAME=OS_SUNOS
  IOEVENT_USE=IOEVENT_USE_PORT
  CFLAGS="$CFLAGS -D_THREAD_SAFE"
  LIBS="$LIBS -lsocket -lnsl -lresolv"
elif [ "$uname" = "AIX" ]; then
  OS_NAME=OS_AIX
  IOEVENT_USE=IOEVENT_USE_NONE
  CFLAGS="$CFLAGS -D_THREAD_SAFE"
elif [ "$uname" = "HP-UX" ]; then
  OS_NAME=OS_HPUX
  IOEVENT_USE=IOEVENT_USE_NONE
else
  OS_NAME=OS_UNKOWN
  IOEVENT_USE=IOEVENT_USE_NONE
fi

check_dirent_field()
{
    field_name=$1
    upper_fname=$(echo $field_name | tr '[a-z]' '[A-Z]')

tmp_src_filename=fast_check_dirent.c
cat <<EOF > $tmp_src_filename
#include <stdio.h>
#include <dirent.h>

int main(int argc, char *argv[])
{
    struct dirent dir;
    dir.$field_name = 1;
    printf("#define HAVE_DIRENT_$upper_fname  %d\n", dir.$field_name);
    return 0;
}
EOF

gcc -o a.out $tmp_src_filename 2>/dev/null && ./a.out
/bin/rm -f a.out $tmp_src_filename

}

tmp_filename=fast_dirent_macros.txt
check_dirent_field d_type   >  $tmp_filename
check_dirent_field d_reclen >> $tmp_filename
check_dirent_field d_namlen >> $tmp_filename
check_dirent_field d_off    >> $tmp_filename

cat <<EOF > src/_os_define.h
#ifndef _OS_DEFINE_H
#define _OS_DEFINE_H

#define OS_BITS  $OS_BITS
#define OFF_BITS $OFF_BITS

#ifndef $OS_NAME
#define $OS_NAME  1
#endif

#ifndef $IOEVENT_USE
#define $IOEVENT_USE  1
#endif

#ifndef HAVE_VMMETER_H
#define HAVE_VMMETER_H $HAVE_VMMETER_H
#endif

#ifndef HAVE_USER_H
#define HAVE_USER_H $HAVE_USER_H
#endif

$(cat $tmp_filename && /bin/rm -f $tmp_filename)

#endif
EOF

pthread_path=''
for path in /lib /lib64 /usr/lib /usr/lib64 /usr/local/lib; do
  if [ -d $path ]; then
    pthread_path=$(find $path -name libpthread.so | head -n 1)
    if [ -n "$pthread_path" ]; then
      break
    fi

    pthread_path=$(find $path -name libpthread.a | head -n 1)
    if [ -n "$pthread_path" ]; then
      break
    fi
  fi
done

if [ -n "$pthread_path" ]; then
  LIBS="$LIBS -lpthread"
  line=$(nm $pthread_path 2>/dev/null | grep -F pthread_rwlockattr_setkind_np | grep -w T)
  if [ -n "$line" ]; then
    CFLAGS="$CFLAGS -DWITH_PTHREAD_RWLOCKATTR_SETKIND_NP=1"
  fi
elif [ -f /usr/lib/libc_r.so ]; then
  line=$(nm -D /usr/lib/libc_r.so 2>/dev/null | grep -F pthread_create | grep -w T)
  if [ -n "$line" ]; then
    LIBS="$LIBS -lc_r"
  fi
fi

sed_replace()
{
    sed_cmd=$1
    filename=$2
    if [ "$uname" = "FreeBSD" ] || [ "$uname" = "Darwin" ]; then
       sed -i "" "$sed_cmd" $filename
    else
       sed -i "$sed_cmd" $filename
    fi
}

cd src
cp Makefile.in Makefile
sed_replace "s#\\\$(CC)#gcc#g" Makefile
sed_replace "s#\\\$(CFLAGS)#$CFLAGS#g" Makefile
sed_replace "s#\\\$(INCS)#$INCS#g" Makefile
sed_replace "s#\\\$(LIBS)#$LIBS#g" Makefile
sed_replace "s#\\\$(TARGET_PREFIX)#$TARGET_PREFIX#g" Makefile
sed_replace "s#\\\$(LIB_VERSION)#$LIB_VERSION#g" Makefile
make $1 $2 $3

if [ "$1" = "clean" ]; then
  /bin/rm -f Makefile _os_define.h
fi
