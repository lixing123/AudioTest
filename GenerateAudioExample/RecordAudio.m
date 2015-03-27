//
//  RecordAudio.m
//  GenerateAudioExample
//
//  Created by 李 行 on 15/3/12.
//  Copyright (c) 2015年 lixing123.com. All rights reserved.
//

#import "RecordAudio.h"
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import "AppDelegate.h"

#define kNumberRecordBuffers	3


typedef struct MyRecorder {
    AudioFileID					recordFile; // reference to your output file
    SInt64						recordPacket; // current packet index in output file
    Boolean						running; // recording state
} MyRecorder;

MyRecorder recorder;
AudioQueueRef queue;

#pragma mark - utility functions -
// generic error handler - if error is nonzero, prints error message and exits program.
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


// get sample rate of the default input device
OSStatus MyGetDefaultInputDeviceSampleRate(Float64 *outSampleRate)
{
    //used in OS X
    /*
     OSStatus error;
     AudioDeviceID deviceID = 0;
     
     // get the default input device
     AudioObjectPropertyAddress propertyAddress;
     UInt32 propertySize;
     propertyAddress.mSelector = kAudioHardwarePropertyDefaultInputDevice;
     propertyAddress.mScope = kAudioObjectPropertyScopeGlobal;
     propertyAddress.mElement = 0;
     propertySize = sizeof(AudioDeviceID);
     error = AudioHardwareServiceGetPropertyData(kAudioObjectSystemObject, &propertyAddress, 0, NULL, &propertySize, &deviceID);
     if (error) return error;
     
     // get its sample rate
     propertyAddress.mSelector = kAudioDevicePropertyNominalSampleRate;
     propertyAddress.mScope = kAudioObjectPropertyScopeGlobal;
     propertyAddress.mElement = 0;
     propertySize = sizeof(Float64);
     error = AudioHardwareServiceGetPropertyData(deviceID, &propertyAddress, 0, NULL, &propertySize, outSampleRate);
     
     return error;*/
    
    //used in iOS
    UInt32 hardwareSampleRate;
    UInt32 size = sizeof(hardwareSampleRate);
    AudioSessionGetProperty(kAudioSessionProperty_CurrentHardwareSampleRate, &size, &hardwareSampleRate);
    
    *outSampleRate = (Float64)hardwareSampleRate;
    return noErr;
}


// Determine the size, in bytes, of a buffer necessary to represent the supplied number
// of seconds of audio data.
static int MyComputeRecordBufferSize(const AudioStreamBasicDescription *format, AudioQueueRef queue, float seconds)
{
    int packets, frames, bytes;
    
    frames = (int)ceil(seconds * format->mSampleRate);
    
    if (format->mBytesPerFrame > 0)						// 1
        bytes = frames * format->mBytesPerFrame;
    else
    {
        UInt32 maxPacketSize;
        if (format->mBytesPerPacket > 0)				// 2
            maxPacketSize = format->mBytesPerPacket;
        else
        {
            // get the largest single packet size possible
            UInt32 propertySize = sizeof(maxPacketSize);	// 3
            checkErr(AudioQueueGetProperty(queue,
                                           kAudioConverterPropertyMaximumOutputPacketSize,
                                           &maxPacketSize,
                                           &propertySize),
                     "couldn't get queue's maximum output packet size");
        }
        if (format->mFramesPerPacket > 0)
            packets = frames / format->mFramesPerPacket;	 // 4
        else
            // worst-case scenario: 1 frame in a packet
            packets = frames;							// 5
        
        if (packets == 0)		// sanity check
            packets = 1;
        bytes = packets * maxPacketSize;				// 6
    }
    return bytes;
}

// Copy a queue's encoder's magic cookie to an audio file.
static void MyCopyEncoderCookieToFile(AudioQueueRef queue, AudioFileID theFile)
{
    UInt32 propertySize;
    
    // get the magic cookie, if any, from the queue's converter
    OSStatus result = AudioQueueGetPropertySize(queue,
                                                kAudioConverterCompressionMagicCookie,
                                                &propertySize);
    
    if (result == noErr && propertySize > 0)
    {
        // there is valid cookie data to be fetched;  get it
        Byte *magicCookie = (Byte *)malloc(propertySize);
        checkErr(AudioQueueGetProperty(queue, kAudioQueueProperty_MagicCookie, magicCookie,
                                       &propertySize), "get audio queue's magic cookie");
        
        // now set the magic cookie on the output file
        checkErr(AudioFileSetProperty(theFile, kAudioFilePropertyMagicCookieData, propertySize, magicCookie),
                 "set audio file's magic cookie");
        free(magicCookie);
    }
}

#pragma mark - audio queue -

// Audio Queue callback function, called when an input buffer has been filled.
static void MyAQInputCallback(void *inUserData, AudioQueueRef inQueue,
                              AudioQueueBufferRef inBuffer,
                              const AudioTimeStamp *inStartTime,
                              UInt32 inNumPackets,
                              const AudioStreamPacketDescription *inPacketDesc)
{
    NSLog(@"MyAQInputCallback...");
    MyRecorder *recorder = (MyRecorder *)inUserData;
    
    // if inNumPackets is greater then zero, our buffer contains audio data
    // in the format we specified (AAC)
    if (inNumPackets > 0)
    {
        // write packets to file
        checkErr(AudioFileWritePackets(recorder->recordFile,
                                       FALSE,
                                       inBuffer->mAudioDataByteSize,
                                       inPacketDesc,
                                       recorder->recordPacket,
                                       &inNumPackets,
                                       inBuffer->mAudioData),
                 "AudioFileWritePackets failed");
        // increment packet index
        recorder->recordPacket += inNumPackets;
    }
    
    //计算音量
    int numChannels = 1;
    UInt32 dataSize = sizeof(AudioQueueLevelMeterState) * numChannels;
    AudioQueueLevelMeterState * levels = (AudioQueueLevelMeterState*)malloc(dataSize);
    
    checkErr(AudioQueueGetProperty(inQueue,
                                   kAudioQueueProperty_CurrentLevelMeterDB,
                                   levels,
                                   &dataSize),
             "getting level meter failed");
    for (int i=0; i<numChannels; i++) {
        NSLog(@"level meter:%f",levels[i].mAveragePower);
    }
    
    // if we're not stopping, re-enqueue the buffer so that it gets filled again
    if (recorder->running)
        checkErr(AudioQueueEnqueueBuffer(inQueue,
                                         inBuffer,
                                         0,
                                         NULL),
                 "AudioQueueEnqueueBuffer failed");
}

@implementation RecordAudio

-(void)start{
    //recorder = {0};
    AudioStreamBasicDescription recordFormat;
    memset(&recordFormat, 0, sizeof(recordFormat));
    
    //we want to record as stereo AAC
    /*recordFormat.mFormatID = kAudioFormatMPEG4AAC;
    recordFormat.mChannelsPerFrame = 1;
    //MyGetDefaultInputDeviceSampleRate(&recordFormat.mSampleRate);
    recordFormat.mSampleRate = 44100;
     */
    
    //now the Linear PCM
    recordFormat.mFormatID = kAudioFormatLinearPCM;
    recordFormat.mSampleRate = 44100;
    recordFormat.mChannelsPerFrame = 2;
    recordFormat.mFramesPerPacket = 1;
    recordFormat.mBytesPerFrame = 4;
    recordFormat.mBytesPerPacket = 4;
    recordFormat.mBitsPerChannel = 16;
    recordFormat.mFormatFlags = kAudioFormatFlagIsBigEndian | kAudioFormatFlagIsPacked | kAudioFormatFlagIsSignedInteger;
    
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSError* error;
    [session setCategory:AVAudioSessionCategoryPlayAndRecord error:&error];
    [session setActive:YES error:&error];
    
    //let core audio fill in other fields of the asbd
    UInt32 propSize = sizeof(recordFormat);
    checkErr(AudioFormatGetProperty(kAudioFormatProperty_FormatInfo,
                                    0,
                                    NULL,
                                    &propSize,
                                    &recordFormat),
             "AudioFormatGetProperty failed");
    
    //init audio queue
    checkErr(AudioQueueNewInput(&recordFormat,
                                MyAQInputCallback,
                                &recorder,
                                NULL,
                                NULL,
                                0,
                                &queue), "AudioQueueNewInput failed") ;
    
    //fill in the recordFormat asbd with asbd of audio queue
    checkErr(AudioQueueGetProperty(queue,
                                   kAudioConverterCurrentOutputStreamDescription,
                                   &recordFormat,
                                   &propSize),
             "Couldn't get queue's format");
    
    //create audio file
    NSString* myFileString = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSURL* myFileURL = [NSURL fileURLWithPath:[myFileString stringByAppendingPathComponent:@"sample.caf"]];
    
    checkErr(AudioFileCreateWithURL((__bridge CFURLRef)myFileURL,
                                    kAudioFileCAFType,
                                    &recordFormat,
                                    kAudioFileFlags_EraseFile,
                                    &recorder.recordFile),
             "AudioFileCreateWithURL failed");
    
    //copy magic cookie of audioqueue to file
    MyCopyEncoderCookieToFile(queue,recorder.recordFile);
    
    //get the optimal size of audio buffers of 0.5 seconds
    int bufferByteSize = MyComputeRecordBufferSize(&recordFormat,queue,0.5);
    NSLog(@"buffer size:%d",bufferByteSize);
    
    //allocate AudioQueueBuffers and enqueue them to the audio queue
    for (int bufferIndex = 0; bufferIndex<kNumberRecordBuffers; bufferIndex++) {
        AudioQueueBufferRef buffer;
        checkErr(AudioQueueAllocateBuffer(queue,
                                          bufferByteSize,
                                          &buffer),
                 "AudioQueueAllocateBuffer failed");
        checkErr(AudioQueueEnqueueBuffer(queue,
                                         buffer,
                                         0,
                                         NULL),
                 "AudioQueueEnqueueBuffer failed");
    }
    
    //enable level metering in order to get volume
    UInt32 enableLM = 1;
    UInt32 size = sizeof(enableLM);
    AudioQueueSetProperty(queue, kAudioQueueProperty_EnableLevelMetering, &enableLM, size);
    
    //start audio queue
    recorder.running = TRUE;
    checkErr(AudioQueueStart(queue,
                             NULL),
             "start audio queue failed");
}

-(void)stop{
    printf("* recording done *\n");
    recorder.running = FALSE;
    checkErr(AudioQueueStop(queue, TRUE), "AudioQueueStop failed");
    
    //cleanup
    //in some cases,the magic cookie is updated
    MyCopyEncoderCookieToFile(queue, recorder.recordFile);
    
    AudioQueueDispose(queue, TRUE);
    AudioFileClose(recorder.recordFile);
}

@end
