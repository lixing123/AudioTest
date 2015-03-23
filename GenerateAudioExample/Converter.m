//
//  Converter.m
//  GenerateAudioExample
//
//  Created by 李 行 on 15/3/20.
//  Copyright (c) 2015年 lixing123.com. All rights reserved.
//

#import "Converter.h"
#include <AudioToolbox/AudioToolbox.h>

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
    AudioStreamBasicDescription    inputFormat;
    AudioStreamBasicDescription    outputFormat;
    
    AudioFileID                    inputFile;
    AudioFileID                    outputFile;
    
    UInt64                         inputFilePacketIndex;
    UInt64                         inputFilePacketCount;
    UInt32                         inputFilePacketMaxSize;
    AudioStreamPacketDescription*  inputfilePacketDescriptions;
    
    void* sourceBuffer;
} MyAudioConverterSettings;

OSStatus MyAudioConverterCallback ( AudioConverterRef inAudioConverter,
                                   UInt32 *ioNumberDataPackets,
                                   AudioBufferList *ioData,
                                   AudioStreamPacketDescription **outDataPacketDescription,
                                   void *inUserData ){
    MyAudioConverterSettings* audioConverterSettings = (MyAudioConverterSettings*)inUserData;
    
    //zero out the audio buffer, in case a failure occurs and we don't read into it successfully
    ioData->mBuffers[0].mData = NULL;
    ioData->mBuffers[0].mDataByteSize = 0;
    
    //if there are not enough packets to satisfy request, then read what's left
    if (audioConverterSettings->inputFilePacketIndex+ *ioNumberDataPackets > audioConverterSettings->inputFilePacketCount) {
        *ioNumberDataPackets = audioConverterSettings->inputFilePacketCount - audioConverterSettings->inputFilePacketIndex;
    }
    
    if (*ioNumberDataPackets==0) {
        return noErr;
    }
    
    //free the buffer that has been used and re-allocate it
    if (audioConverterSettings->sourceBuffer!=NULL) {
        free(audioConverterSettings->sourceBuffer);
        audioConverterSettings->sourceBuffer = NULL;
    }
    
    //calloc(n,size)与malloc的区别：calloc分配n*size大小的空间，并初始化此空间为0;而malloc没有初始化
    audioConverterSettings->sourceBuffer = (void*)calloc(1,
                                                         *ioNumberDataPackets * audioConverterSettings->inputFilePacketMaxSize);
    
    //read some packets from the source file into the buffer
    UInt32 outByteCount = 0;
    OSStatus result = AudioFileReadPackets(audioConverterSettings->inputFile,
                                           NO,
                                           &outByteCount,
                                           audioConverterSettings->inputfilePacketDescriptions,
                                           audioConverterSettings->inputFilePacketIndex,
                                           ioNumberDataPackets,
                                           audioConverterSettings->sourceBuffer);
    //if read to the end of the file, 10.7 returns the kAudioFileEndOfFileError and earlier version returns eofErr
#ifdef MAC_OS_X_VERSION_10_7
    if (result==kAudioFileEndOfFileError && *ioNumberDataPackets) {
        result = noErr;
    }
#else
    if (result==eofErr && *ioNumberDataPackets) {
        result = noErr;
    }
#endif
    else if (result!=noErr) return result;
    
    audioConverterSettings->inputFilePacketIndex += *ioNumberDataPackets;
    ioData->mBuffers[0].mData = audioConverterSettings->sourceBuffer;
    ioData->mBuffers[0].mDataByteSize = outByteCount;
    if (outDataPacketDescription) {
        *outDataPacketDescription = audioConverterSettings->inputfilePacketDescriptions;
    }
    
    
    return noErr;
}

@implementation Converter

-(void)startConvert{
    //open input file
    MyAudioConverterSettings audioConverterSettings = {0};
    NSString* filePath = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingPathComponent:@"sample.caf"];
    //CFURLRef inputFileURL = (__bridge CFURLRef)[NSURL fileURLWithPath:filePath];//会导致出错
    CFURLRef inputFileURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, (__bridge CFStringRef)filePath, kCFURLPOSIXPathStyle, false);
    checkErr(AudioFileOpenURL(inputFileURL,
                              kAudioFileReadPermission,
                              0,
                              &audioConverterSettings.inputFile),
             "AudioFileOpenURL failed");
    CFRelease(inputFileURL);
    
    //get input file's format
    UInt32 size = sizeof(AudioStreamBasicDescription);
    checkErr(AudioFileGetProperty(audioConverterSettings.inputFile,
                                  kAudioFilePropertyDataFormat,
                                  &size,
                                  &audioConverterSettings.inputFormat),
             "Get input file's format failed");
    
    //get total number of packets of the input file
    size = sizeof(UInt64);
    checkErr(AudioFileGetProperty(audioConverterSettings.inputFile,
                                  kAudioFilePropertyAudioDataPacketCount,
                                  &size, &audioConverterSettings.inputFilePacketCount),
             "Couldn't get input file's packet count");
    
    //get the largest packet size of input file
    size = sizeof(UInt32);
    checkErr(AudioFileGetProperty(audioConverterSettings.inputFile,
                                  kAudioFilePropertyMaximumPacketSize,
                                  &size,
                                  &audioConverterSettings.inputFilePacketMaxSize),
             "Couldn't get input file's max packet size");
    
    //create output file's with desired AudioFileBasicDescription
    audioConverterSettings.outputFormat.mSampleRate = 44100;
    audioConverterSettings.outputFormat.mFormatFlags = kAudioFormatFlagIsBigEndian | kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    audioConverterSettings.outputFormat.mChannelsPerFrame = 2;
    audioConverterSettings.outputFormat.mBitsPerChannel = 16;
    audioConverterSettings.outputFormat.mFramesPerPacket = 1;
    audioConverterSettings.outputFormat.mBytesPerFrame = 4;
    audioConverterSettings.outputFormat.mBytesPerPacket = 4;
    audioConverterSettings.outputFormat.mFormatID = kAudioFormatLinearPCM;
    
    //书上用的是output.aif。aif是什么格式???
    filePath = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingPathComponent:@"output.caf"];
    //CFURLRef outputURL = (__bridge CFURLRef)[NSURL fileURLWithPath:filePath];
    CFURLRef outputURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, (__bridge CFStringRef)filePath, kCFURLPOSIXPathStyle, false);
    checkErr(AudioFileCreateWithURL(outputURL,
                                    kAudioFileAIFFType,
                                    &audioConverterSettings.outputFormat,
                                    kAudioFileFlags_EraseFile,
                                    &audioConverterSettings.outputFile),
             "Create output file failed");
    CFRelease(outputURL);
    
    fprintf(stdout, "Converting...\n");
    Convert(&audioConverterSettings);
    
//cleanup:
    checkErr(AudioFileClose(audioConverterSettings.inputFile), "Close input file failed");
    checkErr(AudioFileClose(audioConverterSettings.outputFile), "Close output file failed");
}

void Convert(MyAudioConverterSettings* mySettings){
    //Create the audioConverter object
    AudioConverterRef audioConverter;
    checkErr(AudioConverterNew(&mySettings->inputFormat,
                               &mySettings->outputFormat,
                               &audioConverter),
             "AudioConverterNew failed");
    
    //Determine the Size of a Packet Buffers array and packets-per-buffer count for variable bit rate data so that the buffer is big enough to hold at least one packet
    UInt32 packetsPerBuffer = 0;
    UInt32 outputBufferSize = 32*1024; //32 KB is a good starting point,why???
    UInt32 sizePerPacket = mySettings->inputFormat.mBytesPerPacket;
    if (sizePerPacket==0) {//for VBR format
        UInt32 size = sizeof(sizePerPacket);
        checkErr(AudioConverterGetProperty(audioConverter,
                                           kAudioConverterPropertyMaximumOutputPacketSize,
                                           &size,
                                           &sizePerPacket),
                 "Couldn't get kAudioConverterPropertyMaximumOutputPacketSize");
        
        if (sizePerPacket>outputBufferSize) {
            outputBufferSize = sizePerPacket;
        }
        
        packetsPerBuffer = outputBufferSize/sizePerPacket;
        mySettings->inputfilePacketDescriptions = (AudioStreamPacketDescription*)malloc(sizeof(AudioStreamPacketDescription)*packetsPerBuffer);
    }else{//for CBR format
        packetsPerBuffer = outputBufferSize/sizePerPacket;
    }
    
    UInt8* outputBuffer = (UInt8*)malloc(sizeof(UInt8)*outputBufferSize);
    UInt32 outputFilePacketPosition = 0;
    while (1) {
        AudioBufferList convertedData;
        convertedData.mNumberBuffers = 1;
        convertedData.mBuffers[0].mNumberChannels = mySettings->inputFormat.mChannelsPerFrame;
        convertedData.mBuffers[0].mDataByteSize   = outputBufferSize;
        convertedData.mBuffers[0].mData           = outputBuffer;
        
        UInt32 ioOutputDataPackets = packetsPerBuffer;
        OSStatus result = AudioConverterFillComplexBuffer(audioConverter,
                                                          MyAudioConverterCallback,
                                                          mySettings,
                                                          &ioOutputDataPackets,
                                                          &convertedData,
                                                          (mySettings->inputfilePacketDescriptions?mySettings->inputfilePacketDescriptions:nil));
        if (result||!ioOutputDataPackets) {//finish or fails
            break;
        }
        
        //write the converted data to the output file
        checkErr(AudioFileWritePackets(mySettings->outputFile,
                                       NO,
                                       ioOutputDataPackets,
                                       NULL,
                                       outputFilePacketPosition/mySettings->outputFormat.mBytesPerPacket,
                                       &ioOutputDataPackets,
                                       convertedData.mBuffers[0].mData),
                 "Couldn't write packets to file");
        outputFilePacketPosition += (ioOutputDataPackets * mySettings->outputFormat.mBytesPerPacket);
    }
    AudioConverterDispose(audioConverter);
}

@end
