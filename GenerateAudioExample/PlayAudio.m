//
//  PlayAudio.m
//  GenerateAudioExample
//
//  Created by 李 行 on 15/3/12.
//  Copyright (c) 2015年 lixing123.com. All rights reserved.
//

#import "PlayAudio.h"
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>

#define kNumberPlaybackBuffers 3//number of buffers for playback queue

typedef struct MyPlayer {
    AudioFileID					  playbackFile;
    SInt64                        packetPosition;
    UInt32                        numPacketsToRead;
    AudioStreamPacketDescription  *packetDescs;
    Boolean						  isDone;
} MyPlayer;

static void checkErr(OSStatus error, const char *operation)
{
    if (error == noErr) return;
    
    char errorString[20];
    // see if it appears to be a 4-char-code
    *(UInt32 *)(errorString + 1) = CFSwapInt32HostToBig(error);
    if (isprint(errorString[1]) && isprint(errorString[2]) && isprint(errorString[3]) && isprint(errorString[4])) {
        errorString[0] = errorString[5] = '\'';
        errorString[6] = '\0';
    } else
        // no, format it as an integer
        sprintf(errorString, "%d", (int)error);
    
    fprintf(stderr, "Error: %s (%s)\n", operation, errorString);
    
    exit(1);
}

static void MyAQOutputCallback(void* inUserData,
                               AudioQueueRef inAQ,
                               AudioQueueBufferRef inCompleteAQBuffer){
    NSLog(@"MyAQOuputCallback...");
    MyPlayer* player = (MyPlayer*)inUserData;
    if (player->isDone) {
        return;
    }
    
    //read packet from the audio file and fill it to the buffer
    UInt32 outNumBytes;
    UInt32 nPackets = player->numPacketsToRead;
    checkErr(AudioFileReadPackets(player->playbackFile,
                                  false,
                                  &outNumBytes,
                                  player->packetDescs,
                                  player->packetPosition,
                                  &nPackets,
                                  inCompleteAQBuffer->mAudioData),
             "AudioFileReadPackets failed");
    
    //if successfully read any audio data, enqueue the buffer to the queue
    if (nPackets>0) {
        inCompleteAQBuffer->mAudioDataByteSize = outNumBytes;
        AudioQueueEnqueueBuffer(inAQ,
                                inCompleteAQBuffer,
                                player->packetDescs?nPackets:0,
                                player->packetDescs);
        player->packetPosition += nPackets;
    }else{//at the end of the file
        checkErr(AudioQueueStop(inAQ,
                                false),//this parameter indicates whether should stop the queue immediately.In RecordAudio this is true, but here is false in order for the player to play the remaining buffers.
                 "AudioQueueStop failed");
        player->isDone = YES;
    }
}

//figure out the queue's buffer size, as well as how many packets can be expected to read into each buffer
static void CalculateBytesForTime(AudioFileID inAudioFile,
                                  AudioStreamBasicDescription inAsbd,
                                  float inSeconds,
                                  UInt32* outBufferSize,
                                  UInt32* outNumPackets){
    //get max packet size
    UInt32 maxPacketSize;
    UInt32 propSize = sizeof(maxPacketSize);
    checkErr(AudioFileGetProperty(inAudioFile,
                                  kAudioFilePropertyPacketSizeUpperBound,
                                  &propSize, &maxPacketSize),
             "get max packet size failed");
    
    //为什么buffer size要有max和int?为什么是这2个值???
    static const int maxBufferSize = 0x10000;
    static const int minBufferSize = 0x4000;
    
    if (inAsbd.mFramesPerPacket) {
        *outBufferSize = inAsbd.mSampleRate/inAsbd.mFramesPerPacket*inSeconds;
    }else{
        //make sure the buffer can contain at least one packet
        *outBufferSize = maxBufferSize>maxPacketSize?maxBufferSize:maxPacketSize;
    }
    
    if (*outBufferSize>maxBufferSize && *outBufferSize>maxPacketSize) {
        *outBufferSize = maxBufferSize;
    }else{
        if (*outBufferSize<minBufferSize) {
            *outBufferSize = minBufferSize;
        }
    }
    *outNumPackets = *outBufferSize/maxPacketSize;
}

static void MyCopyEncoderCookieToQueue(AudioFileID playbackFile,
                                       AudioQueueRef queue){
    UInt32 propertySize;
    OSStatus result = AudioFileGetPropertyInfo(playbackFile,
                                               kAudioFilePropertyMagicCookieData,
                                               &propertySize,
                                               NULL);
    if (result==noErr&&propertySize>0) {
        Byte* magicCookie = (UInt8*)malloc(sizeof(UInt8)*propertySize);
        checkErr(AudioFileGetProperty(playbackFile,
                                      kAudioFilePropertyMagicCookieData,
                                      &propertySize,
                                      magicCookie),
                 "get file magic cookie failed");
        checkErr(AudioQueueSetProperty(queue,
                                       kAudioQueueProperty_MagicCookie,
                                       magicCookie,
                                       propertySize),
                 "set audio queue magic cookie failed");
        free(magicCookie);
    }
}

@implementation PlayAudio

-(void)start{
    MyPlayer player = {0};
    
    //open audio file
    NSString* myFileString = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSURL* fileURL = [NSURL fileURLWithPath:[myFileString stringByAppendingPathComponent:@"sample.caf"]];
    checkErr(AudioFileOpenURL((__bridge CFURLRef)fileURL,
                              kAudioFileReadPermission,
                              0,//only use for filename without file extensions or some other cases. Commonly is 0
                              &player.playbackFile),
             "open file failed");
    
    // set up AudioStreamBasicDescription
    AudioStreamBasicDescription asbd;
    UInt32 size = sizeof(asbd);
    checkErr(AudioFileGetProperty(player.playbackFile,
                                  kAudioFilePropertyDataFormat,
                                  &size,
                                  &asbd),
             "Couldn't get file's data format");
    
    AudioQueueRef queue;
    checkErr(AudioQueueNewOutput(&asbd,
                                 MyAQOutputCallback,
                                 &player,
                                 NULL,
                                 NULL,
                                 0,
                                 &queue),
             "AudioQueueNewOutput failed");
    
    //calculate buffer size
    UInt32 bufferByteSize;
    CalculateBytesForTime(player.playbackFile,
                          asbd,
                          0.5,
                          &bufferByteSize,
                          &player.numPacketsToRead);
    
    //alloc packet desription memory for VBR format. CBR format won't use this property
    BOOL isFormatVBR = (asbd.mBytesPerPacket==0||asbd.mFramesPerPacket==0);
    if (isFormatVBR) {
        player.packetDescs = (AudioStreamPacketDescription*)malloc(sizeof(AudioStreamPacketDescription)*player.numPacketsToRead);
    }else{
        player.packetDescs = NULL;
    }
    
    //copy file's magic cookie to queue
    MyCopyEncoderCookieToQueue(player.playbackFile, queue);
    
    //allocate buffers and enqueue them to the queue
    //for playback, the buffers need to be filled with audio data.
    //we call the callback function to fill in the buffers
    AudioQueueBufferRef buffers[kNumberPlaybackBuffers];
    player.isDone = NO;
    player.packetPosition = 0;
    for (int i=0; i<kNumberPlaybackBuffers; i++) {
        checkErr(AudioQueueAllocateBuffer(queue,
                                          bufferByteSize,
                                          &buffers[i]),
                 "AudioQueueAllocateBuffer failed");
        
        //since this callback has to enqueue the buffers to the queue, we don't need to redo it.
        MyAQOutputCallback(&player, queue, buffers[i]);
        
        //if there's no more data available, cancel it -- this only happens when the audio length is less than 0.5*3=1.5 seconds
        if (player.isDone) {
            break;
        }
    }
    
    //start playback queue
    checkErr(AudioQueueStart(queue,
                             NULL),
             "AudioQueueStart failed");
    
    //每隔0.25s检查一次，有没有播放完
    printf("Playing...\n");
    do{
        CFRunLoopRunInMode(kCFRunLoopDefaultMode,
                           0.25,
                           false);
    }while (!player.isDone);
    
    //make sure the last 3 buffers can be played
    //如果播放结束，再等2s，以确保最后3个buffer也被播放完
    CFRunLoopRunInMode(kCFRunLoopDefaultMode,
                       2,
                       false);
    
    player.isDone = true;
    checkErr(AudioQueueStop(queue,
                            true),
             "AudioQueueStop failed");
    AudioQueueDispose(queue, true);
    AudioFileClose(player.playbackFile);
}

@end
