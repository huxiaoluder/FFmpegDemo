//
//  ViewController.m
//  ffmpeg-oc
//
//  Created by 胡校明 on 2017/11/23.
//  Copyright © 2017年 heartbeat. All rights reserved.
//

#import "ViewController.h"
#import "FFmpegManager.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [FFmpegManager logConfigturation];
    
    NSString *inputFile = [NSBundle.mainBundle pathForResource:@"test_yuv422p" ofType:@"mp4"];
    NSLog(@"%@",inputFile);
    
    [FFmpegManager logMetaData:inputFile];
    
    // 沙盒存储
    NSString *outputPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, true).firstObject stringByAppendingPathComponent:@"movies"];
    BOOL ret = [[NSFileManager defaultManager] createDirectoryAtPath:outputPath withIntermediateDirectories:true attributes:nil error:NULL];
    if (!ret) {
        NSLog(@"创建存储路径失败!");
        return;
    }
    NSString *outputFile = [outputPath stringByAppendingPathComponent:@"test.yuv"];
    NSLog(@"%@",outputFile);
    [FFmpegManager decodeLocalVideo:inputFile andSaveYUV:outputFile];
    
    [FFmpegManager decodeLocalAudio:inputFile andSavePCM:outputFile];
}


- (void)testmmm:(nonnull NSString *)str {
    
}


@end
