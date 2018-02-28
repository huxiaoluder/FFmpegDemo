#!/bin/sh

readonly workspace="/usr/local/Custom/workspace"

[ -r $workspace ] || sudo mkdir -p $workspace || exit 1
sudo chown -R ${USER}:admin ${workspace%/*}

cd $workspace
# 修改FFmpeg配置
configure_flags="--enable-cross-compile --disable-debug --disable-programs --disable-doc --enable-pic"
configure_flags="${configure_flags} --enable-gpl --enable-version3"
configure_flags="${configure_flags} --enable-avresample --enable-postproc"

# 编码库需自行编译
if [ "$X264" ]
then # 必须遵守 gpl (gpl协议下的衍生产品,也必须遵守gpl协议)
    configure_flags="${configure_flags} --enable-libx264"
fi

if [ "$FDK_AAC" ]
then
    configure_flags="${configure_flags} --enable-libfdk-aac"
fi

# 配置编译环境
echo "start configuring the compilation environment..."

if [ ! `which yasm` ]
then
    if [ ! `which brew` ]
    then
        echo "start install homebrew..."
        ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)" \
        || exit 1
    fi
    echo "start install yasm..."
    brew install yasm || exit 1
fi

if [ ! `which gas-preprocessor.pl` ]
then
    echo "start install gas-preprocessor..."

    (curl -L -C - -O https://github.com/libav/gas-preprocessor/raw/master/gas-preprocessor.pl)\
    || exit 1
    chmod +x ./gas-preprocessor.pl
    ln -s ${workspace}/gas-preprocessor.pl /usr/local/bin/gas-preprocessor.pl
fi

echo "finish the configuration for compilation environment!"

echo "\nffmpeg version options:\n"\
     "--------------------------------------------------\n"\
     "|   0) latest version dependence homebrew        |\n"\
     "|   1) designated version by yourself            |\n"\
     "--------------------------------------------------\n"

while read -p "Choose a template: " template
do
    if [[ $template = 0 || $template = 1 ]]
    then
        break
    fi
    echo "error: the option '${template}' out of range!"
done

# 配置版本号
case $template in
0) # 使用 homebrew 获取最新版本号
    version=`brew info ffmpeg | grep ffmpeg: | tr -d -c '0-9.'`;;
1) # 指定 ffmpeg 版本
    read -p "please enter ffmpeg version number: " version;;
esac

source=ffmpeg-$version

# 检测 ffmpeg 资源是否存在
if [ ! -r $source ]
then
    url="http://ffmpeg.org/releases/${source}.tar.bz2"
    echo "\ndownloading ${url}..."
    curl -w %{http_code} $url | tar xj || exit 1
fi

# 选择编译平台 iOS 或 android
echo "\nbuilding platform options:\n"\
     "-------------------\n"\
     "|   0) iOS        |\n"\
     "|   1) android    |\n"\
     "-------------------\n"

while read -p "Multiselect separate by space: " PLATFORMS
do
    PLATFORMS=`echo $PLATFORMS | tr -d -c '0-9 '`
    PLATFORMS=($PLATFORMS)
    [[ ${#PLATFORMS[*]} = 0 ]] && continue
    for platform in ${PLATFORMS[*]}
    do
        if [[ $platform -lt 0 || $platform -gt 1 ]]
        then
            echo "error: the option '${platform}' out of range!"\
            && platform="error" && break
        fi
    done
    [[ $platform != "error" ]] && break
done

# ffmpeg_ios 版本库 configure
#***********************************************************************
function build_ios() {
    echo "\nbuilding for iOS..."
    # 添加 android 配置差异
    local ios_configure_flags="${configure_flags}"
    # 编译暂存区(c编译过程中的二进制 .o 文件)
    buildDir=${workspace}/build
    installDir=/usr/local/Custom/ffmpeg-ios/$version
    fatDir=${installDir}/fat

    # 选择 CPU 架构
    archs=("armv7" "arm64" "i386" "x86_64")
    echo "\narchitecture options:\n"\
         "-------------------\n"\
         "|   0) armv7      |\n"\
         "|   1) arm64      |\n"\
         "|   2) i386       |\n"\
         "|   3) x86_64     |\n"\
         "-------------------\n"

    while read -p "Multiselect separate by space: " ARCHS
    do
        ARCHS=`echo $ARCHS | tr -d -c '0-9 '`
        ARCHS=($ARCHS)
        [[ ${#ARCHS[*]} = 0 ]] && continue
        for arch in ${ARCHS[*]}
        do
            # 检测参数正确性
            if [[ $arch -lt 0 || $arch -gt 3 ]]
            then
                echo "error: the option '${arch}' out of range!"\
                && arch="error" && break
            fi
        done
        [[ $arch != "error" ]] && break
    done

    # 支持 iOS SDK 的最低版本
    deployment_target=8.0

    # 根据不同的架构, 配置 ffmpeg/configure
    for arch in ${ARCHS[*]}
    do
        case $arch in
        0 | 1) # 真机
            platform="iPhoneOS"
            cflags="-mios-version-min=${deployment_target} -fembed-bitcode"
            [ $arch = 1 ] && EXPORT="GASPP_FIX_XCODE5=1"
        ;;
        2 | 3) # 模拟器
            platform="iPhoneSimulator"
            cflags="-mios-simulator-version-min=${deployment_target}"
        ;;
        esac

        arch=${archs[$arch]}

        mkdir -p "${buildDir}/${arch}" || exit 1
        cd "${buildDir}/${arch}"

        cflags="-arch ${arch} ${cflags}"

        xcrun_sdk=`echo ${platform} | tr '[:upper:]' '[:lower:]'`
        cc="xcrun -sdk ${xcrun_sdk} clang"

        # force "configure" to use "gas-preprocessor.pl" (FFmpeg 3.3)
        if [ $arch = "arm64" ]
        then
            # 注: arm64 没有默认使用gas-preprocessor.pl, 其他架构默认使用了(并不是没有使用).
            # 所以手动添加 gas-preprocessor.pl (不能改名称)
            as="gas-preprocessor.pl -arch aarch64 -- ${cc}"
        else
            as=$cc
        fi

        cxxflags=$cflags
        ldflags=$cflags

        if [ "$X264" ]
        then
            cflags="${cflags} -I$X264/include"
            ldflags="${ldflags} -L$X264/lib"
        fi

        if [ "$FDK_AAC" ]
        then
            cflags="${cflags} -I${FDK_AAC}/include"
            ldflags="${ldflags} -L${FDK_AAC}/lib"
        fi

        echo "\nbuilding ffmpeg for iOS ${arch}..."

        TMPDIR=${TMPDIR/%\/} ${workspace}/${source}/configure \
                $ios_configure_flags \
                --target-os=darwin \
                --arch=$arch \
                --cc="$cc" \
                --as="$as" \
                --extra-cflags="$cflags" \
                --extra-ldflags="$ldflags" \
                --prefix="${installDir}/${arch}" \
                || exit 1

        make clean && make -j4 install $EXPORT || exit 1
    done

    # lipo fat binary file
    echo "\nlipo every archtecture lib to fat binary"
    mkdir -p $fatDir/lib || exit 1
    cd $installDir/$arch/lib
    cp -R ../include $fatDir
    cp -R ../share $fatDir
    for libName in *.a
    do
        lipo -create `find $installDir -name $libName | sed '/$fat/d'` \
             -o $fatDir/lib/$libName
    done

    cd $workspace
}
#***********************************************************************

# ffmpeg_android 版本库 configure
#***********************************************************************
function build_android() {
    echo "\nbuilding for android...\n"

    cd $source || exit 1

    # 注: 对于低版本的 NDK, 需要修改 configure 文件, 以防止生成的动态库命名不正确

    # 添加 android 配置差异
    local android_configure_flags="${configure_flags} --enable-shared --disable-static \
                                                      --enable-small --enable-asm"
    # 动态库安装路径
    installDir=/usr/local/Custom/ffmpeg-android/$version
    # NDK 路径, 默认为 android studio 自带的 NDK (自带的最新版 ndk-beta版 无法编译)
    ndkDir=/Users/${USER}/Library/Android/sdk/ndk-bundle
    while [ ! -r $NDK ]
    do
        echo "no such file or directory: ${NDK}\n"
        read -p "please enter sure absolute path for NDK: " ndkDir
    done
    # 以 platform 为交叉编译的根路径
    sysrootDir=${ndkDir}/platforms/android-18/arch-arm
    # 工具链的路径 (android 通用架构 armeabi)
    toolchainDir=${ndkDir}/toolchains/arm-linux-androideabi-4.9/prebuilt/darwin-x86_64
    arch=arm
    addi_cflags="-marm"
    cflags="-Os -fpic ${addi_cflags}"
    ldflags="${addi_cflags}"

    if [ "$X264" ]
    then
        cflags="${cflags} -I$X264/include"
        ldflags="${ldflags} -L$X264/lib"
    fi

    if [ "$FDK_AAC" ]
    then
        cflags="${cflags} -I${FDK_AAC}/include"
        ldflags="${ldflags} -L${FDK_AAC}/lib"
    fi

    ./configure \
    $android_configure_flags \
    --target-os=android \
    --arch=$arch \
    --sysroot=$sysrootDir \
    --extra-cflags="$cflags" \
    --extra-ldflags="$ldflags" \
    --cross-prefix=${toolchainDir}/bin/arm-linux-androideabi- \
    --prefix="${installDir}/${arch}"

    make clean && make -j4 install || exit 1

    cd $workspace
}
#***********************************************************************

# 确定编译库的平台
for platform in ${PLATFORMS[*]}
do
    case $platform in
    0)  build_ios;;
    1)  build_android;;
    esac
done

echo "\ncompilation is complete!\n"

while read -p "do you want remove the workspace(y/n): " remove_key
do
    remove=`echo $remove_key | tr 'A-Z' 'a-z'`
    if [ $remove = "y" -o $remove = "yes" ]; then
        rm -rf $workspace && break
    elif [ $remove = "n" -o $remove = "no" ]; then
        break
    fi
    echo "error: '${remove_key}' is unrecognizable!"
done

echo "\nAll libraries are installed in directory: /usr/local/Custom"


























