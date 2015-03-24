//
//  PlayAndRecord.m
//  GenerateAudioExample
//
//  Created by 李 行 on 15/3/20.
//  Copyright (c) 2015年 lixing123.com. All rights reserved.
//

#import "PlayAndRecord.h"
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>

typedef struct MyRecorder{
    AudioStreamBasicDescription inputFormat;
    AudioQueueRef inputQueue;
    
    AudioStreamBasicDescription outputFormat;
    AudioQueueRef outputQueue;
    
    void* currentBuffer;
    size_t bufferSize;
    
    BOOL isRunning;
}MyRecorder;

MyRecorder myRecorder;

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

static UInt32 MyCalculateRecordBufferSize(const AudioStreamBasicDescription* asbd,
                                          AudioQueueRef audioQueue,
                                          float seconds){
    //return 128*1024;
    return 44100*1.0;
}

void MyAudioQueueInputCallback ( void *inUserData,
                                AudioQueueRef inAQ,
                                AudioQueueBufferRef inBuffer,
                                const AudioTimeStamp *inStartTime,
                                UInt32 inNumberPacketDescriptions,
                                const AudioStreamPacketDescription *inPacketDescs ){
    
    MyRecorder* myRecorder = (MyRecorder*)inUserData;
    NSLog(@"input callback");
    
    //copy audio data
    myRecorder->bufferSize = inBuffer->mAudioDataByteSize;
    myRecorder->currentBuffer = malloc(sizeof(UInt8)*myRecorder->bufferSize);
    memcpy(myRecorder->currentBuffer, inBuffer->mAudioData, inBuffer->mAudioDataByteSize);
    
    checkErr(AudioQueueEnqueueBuffer(inAQ,
                                     inBuffer,
                                     0,
                                     NULL),
             "AudioQueue ReEnqueue buffer failed");
    myRecorder->isRunning = YES;
}

void MyAudioQueueOutputCallback( void *inUserData,
                                AudioQueueRef inAQ,
                                AudioQueueBufferRef inBuffer ){
    NSLog(@"output callback");
    
    MyRecorder* myRecorder = (MyRecorder*)inUserData;
    
    if (myRecorder->isRunning) {
        memcpy(inBuffer->mAudioData, myRecorder->currentBuffer, myRecorder->bufferSize);
        inBuffer->mAudioDataByteSize = myRecorder->bufferSize;
        if (myRecorder->bufferSize>0) {
            checkErr(AudioQueueEnqueueBuffer(inAQ,
                                             inBuffer,
                                             0, NULL),
                     "AudioQueueEnqueueBuffer failed");
        }
    }
}

@implementation PlayAndRecord

-(void)start{
    //start recordAndPlay category
    AVAudioSession* session = [AVAudioSession sharedInstance];
    NSError* error;
    [session setCategory:AVAudioSessionCategoryPlayAndRecord error:&error];
    if (error!=noErr) {
        NSLog(@"AVAudioSession set category error:%@",error);
    }
    [session setActive:YES error:&error];
    if (error!=noErr) {
        NSLog(@"AVAudioSession set active error:%@",error);
    }
    
    //initialize the input format
    myRecorder.inputFormat.mFormatID = kAudioFormatLinearPCM;
    myRecorder.inputFormat.mFormatFlags = kAudioFormatFlagIsBigEndian | kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    myRecorder.inputFormat.mSampleRate = 44100;
    myRecorder.inputFormat.mFramesPerPacket = 1;
    myRecorder.inputFormat.mBitsPerChannel = 16;
    myRecorder.inputFormat.mBytesPerFrame = 4;
    myRecorder.inputFormat.mChannelsPerFrame = 2;
    myRecorder.inputFormat.mBytesPerPacket = 4;
    
    //initialize input audio queue
    checkErr(AudioQueueNewInput(&myRecorder.inputFormat,
                                MyAudioQueueInputCallback,
                                &myRecorder,
                                NULL,
                                NULL,
                                0,
                                &myRecorder.inputQueue),
             "AudioQueueNewInput failed");
    
    //initialize and enqueue buffer to audio queue
    UInt32 bufferSize = MyCalculateRecordBufferSize(&myRecorder.inputFormat,
                                                    myRecorder.inputQueue,
                                                    0.5);
    int bufferCount = 3;
    for (int i=0; i<bufferCount; i++) {
        AudioQueueBufferRef buffer;
        checkErr(AudioQueueAllocateBuffer(myRecorder.inputQueue,
                                          bufferSize,
                                          &buffer),
                 "AudioQueueAllocateBuffer failed");
        checkErr(AudioQueueEnqueueBuffer(myRecorder.inputQueue,
                                         buffer,
                                         0,
                                         NULL),
                 "AudioQueueEnqueueBuffer failed");
    }
    
    //start audio queue
    //myRecorder.isRunning = true;
    checkErr(AudioQueueStart(myRecorder.inputQueue,
                             NULL),
             "Start input audio queue failed");
    
    //initialize output asbd
    myRecorder.outputFormat.mFormatID = kAudioFormatLinearPCM;
    myRecorder.outputFormat.mFormatFlags = kAudioFormatFlagIsBigEndian | kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    myRecorder.outputFormat.mSampleRate = 44100;
    myRecorder.outputFormat.mFramesPerPacket = 1;
    myRecorder.outputFormat.mBitsPerChannel = 16;
    myRecorder.outputFormat.mBytesPerFrame = 4;
    myRecorder.outputFormat.mChannelsPerFrame = 2;
    myRecorder.outputFormat.mBytesPerPacket = 4;
    
    //initialize output audio queue
    checkErr(AudioQueueNewOutput(&myRecorder.outputFormat,
                                 MyAudioQueueOutputCallback,
                                 &myRecorder,
                                 NULL,
                                 NULL,
                                 0,
                                 &myRecorder.outputQueue),
             "AudioQueueNewOutput failed");
    
    //wait for 2 seconds
    CFRunLoopRunInMode(kCFRunLoopDefaultMode,
                       2.0,
                       false);
    
    //initialize and enqueue buffer to output queue
    AudioQueueBufferRef buffers[3];
    UInt32 outputBufferSize = MyCalculateRecordBufferSize(&myRecorder.outputFormat,
                                                          myRecorder.outputQueue,
                                                          0.5);
    for (int i=0; i<3; i++) {
        AudioQueueAllocateBuffer(myRecorder.outputQueue,
                                 outputBufferSize,
                                 &buffers[i]);
        MyAudioQueueOutputCallback(&myRecorder,
                                   myRecorder.outputQueue,
                                   buffers[i]);
    }
    
    
    
    checkErr(AudioQueueStart(myRecorder.outputQueue,
                             NULL),
             "Start Output Queue failed");
    
}

@end
