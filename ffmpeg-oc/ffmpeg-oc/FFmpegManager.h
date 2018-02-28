//
//  FFmpegManager.h
//  ffmpeg-oc
//
//  Created by 胡校明 on 2017/11/23.
//  Copyright © 2017年 heartbeat. All rights reserved.
//

#import <Foundation/Foundation.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdocumentation"

// 编解码库
#import <libavcodec/avcodec.h>

// 音视频元数据处理库
#import <libavformat/avformat.h>

// 图像采样像素处理库
#import <libswscale/swscale.h>

// 音频采样数据处理库
#import <libswresample/swresample.h>

// 辅助工具
#import <libavutil/imgutils.h>

#pragma clang pop

@interface FFmpegManager : NSObject

/**
 打印 ffmpeg 配置信息
 */
+ (void)logConfigturation;

/**
 打印视频元数据信息(metaData, 描述数据的数据)

 @param inputFile 文件路径
 */
+ (void)logMetaData:(nonnull NSString *)inputFile;

/**
 视频解码, 默认输出格式为 AV_PIX_FMT_YUV420P
 YUV420P 已经成为大部分视频的通用格式
 带P的格式, plane平面, 按分量先后存储(YYY...UUU...VVV...), 否则交叉存储(YUVYUVYUV...)
 不同格式 Y:UV 可能不同, U:V 始终相同

 @param inputFile 输入文件路径
 @param outputFile 输出文件路径
 */
+ (void)decodeLocalVideo:(nonnull NSString *)inputFile andSaveYUV:(nonnull NSString *)outputFile;

/**
 视频解码, 默认输出格式为 AV_SAMPLE_FMT_S16
 S16 已经能包含人类能健康识别的所有音域, 且大部分移动设备, 不支持浮点型(FLT)的处理
 带P的格式, plane平面, 按声道先后存储(LLL...RRR...), 否则按声道交叉存储(LRLRLR...)

 @param inputFile 输入文件路径
 @param outputFile 输出文件路径
 */
+ (void)decodeLocalAudio:(nonnull NSString *)inputFile andSavePCM:(nonnull NSString *)outputFile;

@end
