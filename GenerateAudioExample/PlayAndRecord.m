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

#define kAudioSampleRate 44100;

typedef struct MyRecorder{
    AudioStreamBasicDescription inputFormat;
    AudioQueueRef inputQueue;
    
    AudioFileID recordFile;
    SInt64 currentPacketPosition;
    
    AudioStreamBasicDescription outputFormat;
    AudioQueueRef outputQueue;
    
    UInt16* currentBuffer;
    UInt16* previousBuffer;//used to remove echo effect
    float echoFactor;
    
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
    return kAudioSampleRate;
}

void MyAudioQueueInputCallback ( void *inUserData,
                                AudioQueueRef inAQ,
                                AudioQueueBufferRef inBuffer,
                                const AudioTimeStamp *inStartTime,
                                UInt32 inNumberPacketDescriptions,
                                const AudioStreamPacketDescription *inPacketDescs ){
    
    MyRecorder* myRecorder = (MyRecorder*)inUserData;
    myRecorder->bufferSize = inBuffer->mAudioDataByteSize;
    myRecorder->previousBuffer = malloc(sizeof(UInt16)*inBuffer->mAudioDataByteSize);
    myRecorder->currentBuffer = malloc(sizeof(UInt16)*myRecorder->bufferSize);
    
    //copy audio data to previousBuffer for later echo effect
    memcpy(myRecorder->previousBuffer,
           myRecorder->currentBuffer,
           myRecorder->bufferSize);
    
    //copy audio data so that we can playback in the MyAudioQueueOutputCallback
    memcpy(myRecorder->currentBuffer,
           inBuffer->mAudioData,
           inBuffer->mAudioDataByteSize);
    
    NSLog(@"buffer size:%zu",myRecorder->bufferSize);
    //try to remove echo effect while recording using headset microphone, but failed
    for (int i=0; i<myRecorder->bufferSize; i++) {
        UInt16 data = CFSwapInt16BigToHost(myRecorder->currentBuffer[i]);
        myRecorder->currentBuffer[i] = CFSwapInt16HostToBig(data - myRecorder->echoFactor*myRecorder->previousBuffer[i]);
    }
    NSLog(@"factor:%f",myRecorder->echoFactor);
    
    //write data to the output file
    checkErr(AudioFileWritePackets(myRecorder->recordFile,
                                   false,
                                   inBuffer->mAudioDataByteSize,
                                   NULL,
                                   myRecorder->currentPacketPosition,
                                   &inNumberPacketDescriptions,
                                   inBuffer->mAudioData),
             "AudioFileWritePackets failed");
    myRecorder->currentPacketPosition += inNumberPacketDescriptions;
    
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
    //set RecordAndPlay category so that the app is able to get recorded data from the microphone
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
    
    //record from the default built-in microphone
    NSArray* inputArray = [[AVAudioSession sharedInstance] availableInputs];
    for (AVAudioSessionPortDescription* desc in inputArray) {
        if ([desc.portType isEqualToString:AVAudioSessionPortBuiltInMic]) {
            NSError* error;
            [[AVAudioSession sharedInstance] setPreferredInput:desc error:&error];
        }
    }
    
    //initialize the input format
    myRecorder.inputFormat.mFormatID = kAudioFormatLinearPCM;
    myRecorder.inputFormat.mFormatFlags = kAudioFormatFlagIsBigEndian | kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    myRecorder.inputFormat.mSampleRate = kAudioSampleRate;
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
    
    //set up file format so that we can write the recorded data to it
    //create audio file
    NSString* myFileString = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSURL* myFileURL = [NSURL fileURLWithPath:[myFileString stringByAppendingPathComponent:@"playAndRecord.caf"]];
    
    checkErr(AudioFileCreateWithURL((__bridge CFURLRef)myFileURL,
                                    kAudioFileCAFType,
                                    &myRecorder.inputFormat,
                                    kAudioFileFlags_EraseFile,
                                    &myRecorder.recordFile),
             "AudioFileCreateWithURL failed");
    
    //start audio queue
    myRecorder.isRunning = true;
    myRecorder.echoFactor = 0.1;
    checkErr(AudioQueueStart(myRecorder.inputQueue,
                             NULL),
             "Start input audio queue failed");
    
    //initialize output asbd
    myRecorder.outputFormat.mFormatID = kAudioFormatLinearPCM;
    myRecorder.outputFormat.mFormatFlags = kAudioFormatFlagIsBigEndian | kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    myRecorder.outputFormat.mSampleRate = kAudioSampleRate;
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

-(void)changeEchoFactor:(float)echoFactor{
    myRecorder.echoFactor = echoFactor;
}

@end
