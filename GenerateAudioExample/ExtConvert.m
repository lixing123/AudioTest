//
//  ExtConvert.m
//  GenerateAudioExample
//
//  Created by 李 行 on 15/3/23.
//  Copyright (c) 2015年 lixing123.com. All rights reserved.
//

#import "ExtConvert.h"
#import <AudioToolbox/AudioToolbox.h>

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

typedef struct MyAudioConverterSettings{
    AudioStreamBasicDescription outputFormat;
    ExtAudioFileRef             inputFile;
    AudioFileID                 outputFile;
} MyAudioConverterSettings;

void Converter(MyAudioConverterSettings* mySettings){
    //32KB is a good start
    UInt32 outputBufferSize = 32*1024;
    UInt32 sizePerPacket = mySettings->outputFormat.mBytesPerPacket;
    UInt32 packetPerBuffer = outputBufferSize/sizePerPacket;
    
    //allocate a buffer for receivingdata from an extended audio file
    UInt8* outputBuffer = (UInt8*)malloc(sizeof(UInt8) * outputBufferSize);
    UInt32 outputFilePacketPosition = 0;//in bytes
    
    while (1) {
        AudioBufferList convertedBuffer;
        convertedBuffer.mNumberBuffers = 1;
        convertedBuffer.mBuffers[0].mNumberChannels = mySettings->outputFormat.mChannelsPerFrame;
        convertedBuffer.mBuffers[0].mDataByteSize = outputBufferSize;
        convertedBuffer.mBuffers[0].mData = outputBuffer;
        
        //read data from the input file
        UInt32 frameCount = packetPerBuffer;
        checkErr(ExtAudioFileRead(mySettings->inputFile,
                                  &frameCount,
                                  &convertedBuffer),
                 "Couldn't read from input file");
        if (frameCount==0) {
            printf("Done reading from file\n");
            return;
        }
        
        //write the data to the output file
        checkErr(AudioFileWritePackets(mySettings->outputFile,
                                       NO,
                                       frameCount,
                                       NULL,
                                       outputFilePacketPosition/mySettings->outputFormat.mBytesPerPacket,
                                       &frameCount,
                                       convertedBuffer.mBuffers[0].mData),
                 "Couldn't write packets to file");
        
        //output packet position
        outputFilePacketPosition += (frameCount*mySettings->outputFormat.mBytesPerPacket);
    }
}

@implementation ExtConvert

-(void)startConvert{
    MyAudioConverterSettings audioConverterSettings = {0};
    
    //open the input file with ExtAudioFile, 比AudioFileOpenURL简单多了，省略了寻找
    NSString* filePath = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingPathComponent:@"sample.caf"];
    CFURLRef inputFileURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, (__bridge CFStringRef)filePath, kCFURLPOSIXPathStyle, false);
    checkErr(ExtAudioFileOpenURL(inputFileURL,
                                 &audioConverterSettings.inputFile),
             "Open File failed");
    
    //define the output format
    audioConverterSettings.outputFormat.mSampleRate = 44100;
    audioConverterSettings.outputFormat.mFormatID = kAudioFormatLinearPCM;
    audioConverterSettings.outputFormat.mFormatFlags = kAudioFormatFlagIsBigEndian | kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    audioConverterSettings.outputFormat.mBytesPerPacket = 4;
    audioConverterSettings.outputFormat.mFramesPerPacket = 1;
    audioConverterSettings.outputFormat.mBytesPerFrame = 4;
    audioConverterSettings.outputFormat.mChannelsPerFrame = 2;
    audioConverterSettings.outputFormat.mBitsPerChannel = 16;
    
    filePath = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingPathComponent:@"output.aif"];
    CFURLRef outputFileURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, (__bridge CFStringRef)filePath, kCFURLPOSIXPathStyle, false);
    checkErr(AudioFileCreateWithURL(outputFileURL,
                                    kAudioFileAIFFType,
                                    &audioConverterSettings.outputFormat,
                                    kAudioFileFlags_EraseFile,
                                    &audioConverterSettings.outputFile),
             "AudioFileCreateWithURL failed");
    CFRelease(outputFileURL);
    
    //set the client data format property of extAudioFile
    checkErr(ExtAudioFileSetProperty(audioConverterSettings.inputFile,
                                     kExtAudioFileProperty_ClientDataFormat,
                                     sizeof(AudioStreamBasicDescription),
                                     &audioConverterSettings.outputFormat),
             "Couldn't set client data format on input ext file");
    
    fprintf(stdout, "Converting...\n");
    Converter(&audioConverterSettings);
    
cleanup:
    ExtAudioFileDispose(audioConverterSettings.inputFile);
    AudioFileClose(audioConverterSettings.outputFile);
}

@end
