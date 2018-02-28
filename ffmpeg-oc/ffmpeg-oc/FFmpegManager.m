//
//  FFmpegManager.m
//  ffmpeg-oc
//
//  Created by 胡校明 on 2017/11/23.
//  Copyright © 2017年 heartbeat. All rights reserved.
//

#import "FFmpegManager.h"

@implementation FFmpegManager

+ (void)logConfigturation {
    const char *configturation = avcodec_configuration();
    fprintf(stdout, "FFmpeg 配置信息: %s\n",configturation);
}

+ (void)logMetaData:(NSString *)inputFile {
    
    // 1. 注册所有 ffmpeg 组件
    av_register_all();
    
    // 2. 打开资源文件
    AVFormatContext *fmt_ctx = NULL;
    const char *url = inputFile.UTF8String;
    if (!url) {
        fprintf(stderr, "error: no such file!\n");
        exit(1);
    }
    int ret = avformat_open_input(&fmt_ctx, url, NULL, NULL);
    if (ret < 0) {
        // char errbuf[AV_ERROR_MAX_STRING_SIZE] = {0};
        // av_strerror(ret, &errbuf[0], AV_ERROR_MAX_STRING_SIZE);
        // av_err2str(ret); 封装好的宏(翻译错误码)
        fprintf(stderr, "打开文件失败!——reason: %s\n", av_err2str(ret));
        exit(1);
    }
    
    // 3. 打印视频元数据
        // 视频的原数据（metadata）信息
    AVDictionaryEntry *preInfo = NULL;
    
    fprintf(stdout, "视频元数据信息:\n");
    
        // av_dict_get 第三个参数 传 NULL 返回第一个匹配到的信息, 不为 NULL, 则返回 传入值 的下一条匹配
    while ((preInfo = av_dict_get(fmt_ctx->metadata, "", preInfo, AV_DICT_IGNORE_SUFFIX)))
        fprintf(stdout, "\t%s=%s\n", preInfo->key, preInfo->value);
    
    // 4. 关闭资源文件
    avformat_close_input(&fmt_ctx);
}

+ (void)decodeLocalVideo:(NSString *)inputFile andSaveYUV:(NSString *)outputFile {
    // 输入文件路径
    const char *input_url = inputFile.UTF8String;
    
    // 输出文件路径
    const char *output_url = outputFile.UTF8String;
    
    // 1. 注册 FFmpeg 所有组件
    av_register_all();
    
    // 2. 打开资源文件(注: 返回的上下文中只获得了资源文件的信息)
    AVFormatContext *fmt_ctx = NULL;
    int ret = avformat_open_input(&fmt_ctx, input_url, NULL, NULL);
    if (ret < 0) {
        fprintf(stderr, "打开文件失败!——reason: %s\n", av_err2str(ret));
        exit(1);
    }
    
    // 3. 获取流(资源文件中所有种类的流)信息(注: 在上下文中的填充了流的信息)
    ret = avformat_find_stream_info(fmt_ctx, NULL);
    if (ret < 0) {
        fprintf(stderr, "获取流信息失败!——reason: %s\n", av_err2str(ret));
        exit(1);
    }
    
    // 4. 根据视频码流信息获取视频码流(索引)
        // AVStream **streams; 所有流的指针数组
        // unsigned int nb_streams; 资源文件中流的总数
        // AVCodecParameters *codecpar; 流的解码器参数(信息)
    AVCodecParameters *deCodecpar = NULL; // 定义指向解码器参数的指针(只是引用, 不需要释放)
    int video_index = -1; // 定义视频码流在 steams 中的索引
    for (int i = 0; i < fmt_ctx->nb_streams; ++i) {
        if (fmt_ctx->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {
            deCodecpar = fmt_ctx->streams[i]->codecpar;
             video_index = i;
            break;
        }
    }
    if (video_index == -1) {
        fprintf(stderr, "error: 未找到视频码流!\n");
        exit(1);
    }
 
    // 5. 根据视频码流中的解码器参数, 查找对应的解码器(注: 属性 codec 已废弃, 使用 codecpar 替代)
    AVCodec *decodec = avcodec_find_decoder(deCodecpar->codec_id);
    if (!decodec) {
        fprintf(stderr, "error: 未找到对应的解码器!\n");
        exit(1);
    }
    
        // 实例化解码器上下文
    AVCodecContext *dec_ctx = avcodec_alloc_context3(decodec);
    if (!dec_ctx) {
        fprintf(stderr, "error: 实例化解码器上下文失败!\n");
        exit(1);
    }
        // video_stream->codec⬇️
        // 原有的 AVCodecContext *codec 被废弃, 使用自己创建的会报错, 解决方案如下:
        // 拷贝原有的解码器参数 (注: 初始化一些必要的解码器参数, 否则会报错)
    ret = avcodec_parameters_to_context(dec_ctx, deCodecpar);
    if (ret < 0) {
        fprintf(stderr, "初始化解码器参数失败!——reason: %s\n", av_err2str(ret));
        exit(1);
    }
    
        /**
         For some codecs, such as msmpeg4 and mpeg4, width and height
         MUST be initialized there because this information is not
         available in the bitstream.
         */
    
        // 打开解码器
    ret = avcodec_open2(dec_ctx, decodec, NULL);
    if (ret < 0) {
        fprintf(stderr, "打开解码器失败!——reason: %s\n", av_err2str(ret));
        exit(1);
    }
    fprintf(stdout, "视频解码器名称: %s\n", decodec->name);
    
    
    /*----------------------------6.2 解码环境参数-----------------------------*/
        // 注: 这里的 packet, frame 都只是容器而已, 用于保存数据的指针, 数据的内存是有 ffmpeg 分配好的
        // 为将要读取到的数据包分配元数据内存
    AVPacket *packet = av_packet_alloc();
    
        // 为解码后的数据分配元数据内存, 其中参数由 avcodec_receive_frame() 函数填充
    AVFrame *dec_frame = av_frame_alloc();
    

    /*---------------------------7.2 格式转换环境参数---------------------------*/
        // 为图片格式转换提供上下文
    struct SwsContext *sws_ctx = NULL;
    
        // 定义转换数据所需的容器
    AVFrame *cnv_frame = NULL;
    
        // 定义输出缓冲区(用来接收转换后的像素数据)
    const uint8_t *cnv_data_buf = NULL;
    
        // 原格式非 YUV420P, 才需要转换, 并提供图形转换上下文
        // 视频解码默认解码为原视频用的编码格式, 原视频 metadata 数据中, 有保存信息
    if (dec_ctx->pix_fmt != AV_PIX_FMT_YUV420P) {
        sws_ctx = sws_getContext(dec_ctx->width, dec_ctx->height, dec_ctx->pix_fmt,     // 初始参数
                                 dec_ctx->width, dec_ctx->height, AV_PIX_FMT_YUV420P,   // 目标参数
                                 SWS_FAST_BILINEAR, // 转换算法
                                 NULL, NULL, NULL);
        // 算法: SWS_FAST_BILINEAR 综合性能和效果最好(不确定拉伸或缩放时使用)
        // 算法: SWS_POINT 缩放图片, 性能高
        // 算法: SWS_AREA  拉伸图片, 性能高
        if (!sws_ctx) {
            fprintf(stderr, "error: 初始化图片转换上下文失败!\n");
            exit(1);
        }
        
        // 为输出的转换数据分配元数据内存, 其中参数由用户手动填充
        cnv_frame = av_frame_alloc();
        
        // 首先要分配数据缓冲区, YUV422P格式 的缓冲区
        // 计算缓冲区大小
        int buf_size = av_image_get_buffer_size(AV_PIX_FMT_YUV420P, // 像素格式
                                                dec_ctx->width, // 图像宽度
                                                dec_ctx->height, // 图像高度
                                                1); // 按 1 字节对齐
        // 为输出缓冲区分配内存
        cnv_data_buf = (uint8_t *)av_malloc(buf_size);
        // 以上两步, 可以综合为一步➡️av_image_alloc(...)
        
        // 为 cnv_frame 填充参数
        ret = av_image_fill_arrays(cnv_frame->data,     // 被填充的 data 像素数据指针数组
                                   cnv_frame->linesize, // 被填充的对应像素格式和图片宽度的 行字节大小
                                   cnv_data_buf,        // 目标缓冲区指针, 用以填充 cnv_frame->data 的元素
                                   AV_PIX_FMT_YUV420P,  // 图片像素格式
                                   dec_ctx->width,      // 图片宽度
                                   dec_ctx->height,     // 图片高度
                                   1);                  // 按 1 字节对齐
        if (ret < 0) {
            fprintf(stderr, "error: 初始化图片转换上下文失败!\n");
            exit(1);
        }
    }
    
    /*---------------------------8.2 创建数据本输出文件---------------------------*/
        // 打开文件
    FILE *out_file = fopen(output_url, "wb+");
    if (!out_file) {
        fprintf(stderr, "error: 打开输出文件失败!\n");
        exit(1);
    }
    
        // 计算一帧数据, 需要保存的数据分量大小
    int y_size = dec_ctx->width * dec_ctx->height;
    int u_size = y_size / 4;
    int v_size = y_size / 4;


    // 6.1 读取视频流中的压缩数据
    while (av_read_frame(fmt_ctx, packet) == 0) {
        // 判断数据包的类型
        if (packet->stream_index == video_index) { // 视频数据包
            // 为解码器提供原始数据包
            // 注: 在一个 packet 数据包, 未被 receive 完时, 不会发送新的压缩数据
            ret = avcodec_send_packet(dec_ctx, packet);
            if (ret < 0) {
                fprintf(stderr, "发送视频压缩数据包失败!––reason: %s", av_err2str(ret));
                exit(1);
            }
            
            // 开始解码, 并获得视频解码数据
            // 注: 在没有获得一帧的完整数据时, 会返回资源不可用的错, 这是合理的
            ret = avcodec_receive_frame(dec_ctx, dec_frame);
            /**
             注: 这里与 ffmpeg 的 demo 不同, 因为实际上述两个函数, 已经对 不完整的帧进行了处理,
                 在循环的时候:
                 a. 当 packet 还包含能解压出的完整的一帧数据时, 不会发送新的 packet
                 b. 若 packet 不能解压出完整的一帧数据时, 会返回 AVERROR(EAGAIN) 或 AVERROR_EOF 错误码,
                    这种情况下, 会整合剩下的压缩数据与新的压缩数据, 并发送新的 packet
             实际上 avcodec_send_packet 中发送的 packet 已经被整理成了一个 packet 只能完整解码出对应一帧图片的数据量
             */
            if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF) {
                continue; // 成功解码才能继续处理像素, 否则会出现异常
            } else if (ret < 0) {
                fprintf(stderr, "解码数据失败!––reason: %s", av_err2str(ret));
                exit(1);
            }
            
    // 7.1 转换图片像素格式
            if (sws_ctx) { // 需要转换
                // 转换图片像素格式
                sws_scale(sws_ctx, // 像素转换上下文
                          (const uint8_t *const *)(dec_frame->data), // 原始解码数据
                          dec_frame->linesize,  // 原图片中每一行,所占的字节数.如: RGB24格式->(width * 3)Byte
                          0, // 从数据中的哪个位置(第一行开始位置 0 算起)开始处理
                          dec_frame->height,    // 图片高度
                          cnv_frame->data,      // 输出转换数据
                          cnv_frame->linesize); // 输出图片中每一行, 所占的字节数
                
                // 8.1 保存转换后的数据
                fwrite(cnv_frame->data[0], 1, y_size, out_file);
                fwrite(cnv_frame->data[1], 1, u_size, out_file);
                fwrite(cnv_frame->data[2], 1, v_size, out_file);
            } else { // 不需要转换
                // 8.1 直接保存
                fwrite(dec_frame->data[0], 1, y_size, out_file);
                fwrite(dec_frame->data[1], 1, u_size, out_file);
                fwrite(dec_frame->data[2], 1, v_size, out_file);
            }
            
        }
    }
    
    fprintf(stdout, "视频解码完成, 一共%d帧.\n", dec_ctx->frame_number);
    
    fclose(out_file);
    if (dec_ctx->pix_fmt != AV_PIX_FMT_YUV420P) {
        av_free((void *)cnv_data_buf);  // a
        av_frame_free(&cnv_frame);      // b
        sws_freeContext(sws_ctx);       // c
    }
    av_frame_free(&dec_frame);          // d
    av_packet_free(&packet);            // e
    avformat_close_input(&fmt_ctx);     // f
    // b,d,e,f 在内部处理了空指针, 并且释放内存后,对指针进行了置空, 重复调用不会报错(doublefree)
    // 注: 置空指针操作, 需要参数为 &Point, 以获得指针变量的地址
    // a,c 在内部处理了空指针, 但在释放内存后, 无法对指针进行置空, 重复调用会报错(doublefree)
}

+ (void)decodeLocalAudio:(NSString *)inputFile andSavePCM:(NSString *)outputFile {
    // 输入文件
    const char *input_url = inputFile.UTF8String;
    
    // 输出文件
    const char *output_url = outputFile.UTF8String;
    
    // 1. 注册 FFmpeg 所有组件
    av_register_all();
    
    // 2. 打开资源文件(获取上下文信息)
    AVFormatContext *fmt_ctx = NULL;
    int ret = avformat_open_input(&fmt_ctx, input_url, NULL, NULL);
    if (ret < 0) {
        fprintf(stderr, "打开文件失败!––reason: %s\n", av_err2str(ret));
        exit(1);
    }

    // 3. 获取数据流信息
    ret = avformat_find_stream_info(fmt_ctx, NULL);
    if (ret < 0) {
        fprintf(stderr, "获取流信息失败!––reason: %s\n", av_err2str(ret));
        exit(1);
    }
    
    // 4. 遍历数据流, 获取音频流索引
    AVCodecParameters *deCodecpar = NULL; // 解码器参数的引用
    int audio_index = -1; // 音频流索引
    for (int i = 0; i < fmt_ctx->nb_streams; ++i) {
        if (fmt_ctx->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_AUDIO) {
            deCodecpar = fmt_ctx->streams[i]->codecpar;
            audio_index = i;
        }
    }
    if (audio_index == -1) {
        fprintf(stderr, "error: 未找到音频码流!\n");
        exit(1);
    }
    
    // 5. 根据解码器参数, 查找对应的解码器
    AVCodec *decodec = avcodec_find_decoder(deCodecpar->codec_id);
    if (!decodec) {
        fprintf(stderr, "error: 未找到对应的解码器!\n");
        exit(1);
    }
    
        // 实例化解码器上下文
    AVCodecContext *dec_ctx = avcodec_alloc_context3(decodec);
    if (!dec_ctx) {
        fprintf(stderr, "error: 实例化解码器上下文失败!\n");
        exit(1);
    }
    
        // 为解码器上下文填充参数
    ret = avcodec_parameters_to_context(dec_ctx, deCodecpar);
    if (ret < 0) {
        fprintf(stderr, "初始化解码器参数失败!––reason: %s\n", av_err2str(ret));
        exit(1);
    }
    
        // 打开解码器
    ret = avcodec_open2(dec_ctx, decodec, NULL);
    if (ret < 0) {
        fprintf(stderr, "打开解码器失败!––reason: %s\n", av_err2str(ret));
        exit(1);
    }
    
    fprintf(stdout, "音频解码器名称: %s\n", decodec->name);
    
    
    /*----------------------------6.2 解码环境参数-----------------------------*/
        // 压缩数据包容器
    AVPacket *packet = av_packet_alloc();
    
        // 音频解码数据容器
    AVFrame *dec_frame = av_frame_alloc();
    
    
    /*---------------------------7.2 格式转换环境参数---------------------------*/
        // 定义音频格式转换上下文
    SwrContext *swr_ctx = NULL;
    
        // 定义转换数据所需的容器
    AVFrame *cnv_frame = NULL;
    
        // 定义输出缓冲区(用来接收转换后的像素数据)
    const uint8_t *cnv_data_buf = NULL;
    
        // 转换格式为 AV_SAMPLE_FMT_S16, 因为大部分移动设备不支持浮点型处理
    if (dec_ctx->sample_fmt != AV_SAMPLE_FMT_S16) {
        // swr_ctx = swr_alloc(); 创建一个 SwrContext
        /**
         为 swr_ctx 设置参数
         旧接口: av_opt_set_...(); 系列函数来设置参数(头文件: #import <libavutil/opt.h>)
         若解码上下文中没有得到声道布局, 可以使用⬇️
         av_get_default_channel_layout(dec_ctx->channels)
         */
        swr_ctx = swr_alloc_set_opts(swr_ctx, // 可以传事先先创建的, 也可以传NULL, 为NULL时, 会自动创建一个结构, 并返回指针
                                     dec_ctx->channel_layout,   // 输出声道布局
                                     AV_SAMPLE_FMT_S16,         // 输出采样格式(位深及存储格式)
                                     dec_ctx->sample_rate,      // 输出采样精度(HZ)
                                     dec_ctx->channel_layout,   // 输入声道布局
                                     dec_ctx->sample_fmt,       // 输入采样格式(位深及存储格式)
                                     dec_ctx->sample_rate,      // 输入采样精度(HZ)
                                     0,                         // 日志偏移量
                                     NULL);                     // 父类型日志上下文
        if (!swr_ctx) {
            fprintf(stderr, "error: 实例化音频转换上下文失败!\n");
            exit(1);
        }
        // 初始化 音频采样转换上下文
        swr_init(swr_ctx);
        
        // 计算每一帧含有音频样本的最大容量
        size_t max_buff_size = dec_ctx->channels * av_get_bytes_per_sample(dec_ctx->sample_fmt);
        
        // 实例化音频采样数据缓冲区
//        cnv_data_buf = av_malloc(<#size_t size#>);
        
        av_samples_alloc(<#uint8_t **audio_data#>, <#int *linesize#>, <#int nb_channels#>, <#int nb_samples#>, <#enum AVSampleFormat sample_fmt#>, <#int align#>);
//        cnv_data_buf = av_samples_alloc_array_and_samples(<#uint8_t ***audio_data#>, <#int *linesize#>, <#int nb_channels#>, <#int nb_samples#>, <#enum AVSampleFormat sample_fmt#>, <#int align#>);
    }
    
    
        av_samples_fill_arrays(<#uint8_t **audio_data#>, <#int *linesize#>, <#const uint8_t *buf#>, <#int nb_channels#>, <#int nb_samples#>, <#enum AVSampleFormat sample_fmt#>, <#int align#>)


    // 6.1 读取音频流, 获得压缩数据包
    while (av_read_frame(fmt_ctx, packet) >= 0) {
        // 判断数据包类型
        if (packet->stream_index == audio_index) { // 音频压缩数据
            // 为解码器提供压缩数据包
            ret = avcodec_send_packet(dec_ctx, packet);
            if (ret < 0) {
                fprintf(stderr, "发送音频压缩数据包失败!––reason: %s", av_err2str(ret));
                exit(1);
            }
            
            // 开始解码, 并获取音频解码数据
            ret = avcodec_receive_frame(dec_ctx, dec_frame);
            if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF) continue; // 成功解码才能继续处理音频采样, 否则会出现异常
            else if (ret < 0) {
                fprintf(stderr, "解码数据失败!––reason: %s", av_err2str(ret));
                exit(1);
            }
            
    // 7.1 转换数据格式
            if (swr_ctx) {
//                swr_convert(swr_ctx, <#uint8_t **out#>, <#int out_count#>, <#const uint8_t **in#>, <#int in_count#>)
//                swr_convert_frame(<#SwrContext *swr#>, <#AVFrame *output#>, <#const AVFrame *input#>)
            } else {
                
            }
        }
    }
    
    printf("音频解码完成, 一共%d帧.\n", dec_ctx->frame_number);
    
    
    
}

@end

















