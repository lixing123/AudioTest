//
//  ExtAudioFileMixer.m
//  GenerateAudioExample
//
//  Created by 李 行 on 15/2/26.
//  Copyright (c) 2015年 lixing123.com. All rights reserved.
//

#import "ExtAudioFileMixer.h"
#import <AudioToolbox/AudioToolbox.h>

@implementation ExtAudioFileMixer

static void checkErr(OSStatus error, const char* operation){
    if (error==noErr) {
        return;
    }
    
    char errorString[20];
    *(UInt32 *)(errorString+1) = CFSwapInt32HostToBig(error);
    if (isprint(errorString[1]) && isprint(errorString[2]) && isprint(errorString[3]) && isprint(errorString[4])) {
        errorString[0] = errorString[5] = '\'';
        errorString[6] = '\0';
    }else{
        sprintf(errorString, "%d",(int)error);
    }
    fprintf(stderr, "Error: %s (%s)\n",operation,errorString);
}

+ (OSStatus)mixAudio:(NSString *)audioPath1
            andAudio:(NSString *)audioPath2
              toFile:(NSString *)outputPath
  preferedSampleRate:(float)sampleRate
{
    OSStatus							err = noErr;
    AudioStreamBasicDescription			inputFileFormat1;
    AudioStreamBasicDescription			inputFileFormat2;
    AudioStreamBasicDescription			converterFormat;
    UInt32								thePropertySize = sizeof(inputFileFormat1);
    ExtAudioFileRef						inputAudioFileRef1 = NULL;
    ExtAudioFileRef						inputAudioFileRef2 = NULL;
    ExtAudioFileRef						outputAudioFileRef = NULL;
    AudioStreamBasicDescription			outputFileFormat;
    
    NSURL *inURL1 = [NSURL fileURLWithPath:audioPath1];
    NSURL *inURL2 = [NSURL fileURLWithPath:audioPath2];
    NSURL *outURL = [NSURL fileURLWithPath:outputPath];
    
    //打开输入文件
    err = ExtAudioFileOpenURL((__bridge CFURLRef)inURL1, &inputAudioFileRef1);
    checkErr(err, "couldn't open file of inURL1");
    
    err = ExtAudioFileOpenURL((__bridge CFURLRef)inURL2, &inputAudioFileRef2);
    checkErr(err, "couldn't open file of inURL2");
    
    // 获取input文件的format
    bzero(&inputFileFormat1, sizeof(inputFileFormat1));
    err = ExtAudioFileGetProperty(inputAudioFileRef1, kExtAudioFileProperty_FileDataFormat,
                                  &thePropertySize, &inputFileFormat1);
    checkErr(err, "get fileRef1 property kExtAudioFileProperty_FileDataFormat failed");
    
    //仅支持单/双声道
    if (inputFileFormat1.mChannelsPerFrame > 2)
    {
        err = kExtAudioFileError_InvalidDataFormat;
        goto reterr;
    }
    
    bzero(&inputFileFormat2, sizeof(inputFileFormat2));
    //inputFileFormat2的mBytesPerFrame会出现为0的情况，需要特殊处理
    err = ExtAudioFileGetProperty(inputAudioFileRef2, kExtAudioFileProperty_FileDataFormat,
                                  &thePropertySize, &inputFileFormat2);
    if (err)
    {
        goto reterr;
    }
    
    //仅支持单/双声道
    if (inputFileFormat2.mChannelsPerFrame > 2)
    {
        err = kExtAudioFileError_InvalidDataFormat;
        goto reterr;
    }
    
    int numChannels = MAX(inputFileFormat1.mChannelsPerFrame, inputFileFormat2.mChannelsPerFrame);

    //通过设置kExtAudioFileProperty_ClientDataFormat来将输入文件转换成Linear pcm格式
    AudioFileTypeID audioFileTypeID = kAudioFileCAFType;
    Float64 mSampleRate = sampleRate? sampleRate : MAX(inputFileFormat1.mSampleRate, inputFileFormat2.mSampleRate);
    [self _setDefaultAudioFormatFlags:&converterFormat sampleRate:mSampleRate numChannels:inputFileFormat1.mChannelsPerFrame];
    err = ExtAudioFileSetProperty(inputAudioFileRef1, kExtAudioFileProperty_ClientDataFormat,
                                  sizeof(converterFormat), &converterFormat);
    if (err)
    {
        goto reterr;
    }
    [self _setDefaultAudioFormatFlags:&converterFormat sampleRate:mSampleRate numChannels:inputFileFormat2.mChannelsPerFrame];
    err = ExtAudioFileSetProperty(inputAudioFileRef2, kExtAudioFileProperty_ClientDataFormat,
                                  sizeof(converterFormat), &converterFormat);
    if (err)
    {
        goto reterr;
    }
    
    // Handle the case of reading from a mono input file and writing to a stereo
    // output file by setting up a channel map. The mono output is duplicated
    // in the left and right channel.
    
    //处理输入为单声道，输出为双声道的情况，通过设置channel map//需要处理吗？？？
    /*if (inputFileFormat1.mChannelsPerFrame == 1 && numChannels == 2) {
        SInt32 channelMap[2] = { 0, 0 };
        // Get the underlying AudioConverterRef
        AudioConverterRef convRef = NULL;
        UInt32 size = sizeof(AudioConverterRef);
        //kExtAudioFileProperty_AudioConverter是只读属性，可以修改吗？？？
        err = ExtAudioFileGetProperty(inputAudioFileRef1, kExtAudioFileProperty_AudioConverter, &size, &convRef);
        if (err)
        {
            goto reterr;
        }
        assert(convRef);
        err = AudioConverterSetProperty(convRef, kAudioConverterChannelMap, sizeof(channelMap), channelMap);
        //可能会失败，代码561211770:Operation could not be completed kAudioConverterErr_BadPropertySizeError
        if (err)
        {
            //goto reterr;
        }
    }
    if (inputFileFormat2.mChannelsPerFrame == 1 && numChannels == 2) {
        SInt32 channelMap[2] = { 0, 0 };
        // Get the underlying AudioConverterRef
        AudioConverterRef convRef = NULL;
        UInt32 size = sizeof(AudioConverterRef);
        err = ExtAudioFileGetProperty(inputAudioFileRef2, kExtAudioFileProperty_AudioConverter, &size, &convRef);
        if (err)
        {
            goto reterr;
        }
        assert(convRef);
        err = AudioConverterSetProperty(convRef, kAudioConverterChannelMap, sizeof(channelMap), channelMap);
        if (err)
        {
            //goto reterr;
        }
    }
    */
    
    // Output file is typically a caff file, but the user could emit some other
    // common file types. If a file exists already, it is deleted before writing
    // the new audio file.
    [self _setDefaultAudioFormatFlags:&outputFileFormat sampleRate:mSampleRate numChannels:numChannels];
    UInt32 flags = kAudioFileFlags_EraseFile;
    err = ExtAudioFileCreateWithURL((__bridge CFURLRef)outURL, audioFileTypeID, &outputFileFormat,
                                    NULL, flags, &outputAudioFileRef);
    if (err)
    {
        // -48 means the file exists already
        goto reterr;
    }
    assert(outputAudioFileRef);
    
    // ???哪有converter???
    // Enable converter when writing to the output file by setting the client
    // data format to the pcm converter we created earlier.
    err = ExtAudioFileSetProperty(outputAudioFileRef, kExtAudioFileProperty_ClientDataFormat,
                                  sizeof(outputFileFormat), &outputFileFormat);
    if (err)
    {
        goto reterr;
    }
    
    // Buffer to read from source file and write to dest file
    UInt16 bufferSize = 8192;
    
    SInt16 * buffer1 = malloc(bufferSize);
    SInt16 * buffer2 = malloc(bufferSize);
    //SInt16 * outputBuffer = malloc(bufferSize);
    
    AudioBufferList conversionBuffer1;
    conversionBuffer1.mNumberBuffers = 1;
    conversionBuffer1.mBuffers[0].mNumberChannels = inputFileFormat1.mChannelsPerFrame;
    conversionBuffer1.mBuffers[0].mDataByteSize = bufferSize;
    conversionBuffer1.mBuffers[0].mData = buffer1;
    
    AudioBufferList conversionBuffer2;
    conversionBuffer2.mNumberBuffers = 1;
    conversionBuffer2.mBuffers[0].mNumberChannels = inputFileFormat2.mChannelsPerFrame;
    conversionBuffer2.mBuffers[0].mDataByteSize = bufferSize;
    conversionBuffer2.mBuffers[0].mData = buffer2;
    
    AudioBufferList outBufferList;
    outBufferList.mNumberBuffers = 1;
    outBufferList.mBuffers[0].mNumberChannels = outputFileFormat.mChannelsPerFrame;
    outBufferList.mBuffers[0].mDataByteSize = bufferSize;
    //outBufferList.mBuffers[0].mData = outputBuffer;
    
    UInt32 numFramesToReadPerTime = INT_MAX;
    UInt8 bitOffset = 8 * sizeof(SInt16);
    
    while (TRUE) {
        conversionBuffer1.mBuffers[0].mDataByteSize = bufferSize;
        conversionBuffer2.mBuffers[0].mDataByteSize = bufferSize;
        outBufferList.mBuffers[0].mDataByteSize = bufferSize;
        
        UInt32 frameCount1 = numFramesToReadPerTime;
        UInt32 frameCount2 = numFramesToReadPerTime;
        
        //mBytesPerFrame will be 0 when input file format is wav and channel number is 1
        //need to be fixed
        if (inputFileFormat1.mBytesPerFrame)
        {
            frameCount1 = bufferSize/inputFileFormat1.mBytesPerFrame;
        }
        if (inputFileFormat2.mBytesPerFrame)
        {
            frameCount2 = bufferSize/inputFileFormat2.mBytesPerFrame;
        }
        
        // Read a chunk of input
        err = ExtAudioFileRead(inputAudioFileRef1, &frameCount1, &conversionBuffer1);
        
        if (err) {
            goto reterr;
        }
        
        err = ExtAudioFileRead(inputAudioFileRef2, &frameCount2, &conversionBuffer2);
        
        if (err) {
            goto reterr;
        }
        // If no frames were returned, conversion is finished
        if (frameCount1 == 0 && frameCount2 == 0)
            break;
        
        UInt32 frameCount = MAX(frameCount1, frameCount2);
        
        outBufferList.mBuffers[0].mDataByteSize = frameCount * outputFileFormat.mBytesPerFrame;
        
        SInt16 * outputBuffer = malloc(bufferSize);
        UInt32 length = frameCount * 2;
        for (int j =0; j < length; j++)
        {
            SInt32 sValue =0;
            SInt16 value1 = (SInt16)*(buffer1+j);   //-32768 ~ 32767
            SInt16 value2 = (SInt16)*(buffer2+j);   //-32768 ~ 32767
            sValue = value1*3 + value2;
            *(outputBuffer +j) = sValue;
        }
        
        // Write pcm data to output file
        //NSLog(@"frame count (%u, %u, %u)", (unsigned int)frameCount, (unsigned int)frameCount1, (unsigned int)frameCount2);
        outBufferList.mBuffers[0].mData = outputBuffer;
        
        err = ExtAudioFileWrite(outputAudioFileRef, frameCount, &outBufferList);
        
        if (err) {
            goto reterr;
        }
        free(outputBuffer);
    }
    
reterr:
    /*if (buffer1)
        free(buffer1);
    
    if (buffer2)
        free(buffer2);
    
    if (outBuffer)
        free(outBuffer);
    
    if (inputAudioFileRef1)
        ExtAudioFileDispose(inputAudioFileRef1);
    
    if (inputAudioFileRef2)
        ExtAudioFileDispose(inputAudioFileRef2);
    
    if (outputAudioFileRef)
        ExtAudioFileDispose(outputAudioFileRef);
    */
    return err;
}

// Set flags for default audio format on iPhone OS

+ (void) _setDefaultAudioFormatFlags:(AudioStreamBasicDescription*)audioFormatPtr
                          sampleRate:(Float64)sampleRate
                         numChannels:(NSUInteger)numChannels
{
    bzero(audioFormatPtr, sizeof(AudioStreamBasicDescription));
    
    audioFormatPtr->mFormatID = kAudioFormatLinearPCM;
    audioFormatPtr->mSampleRate = sampleRate;
    audioFormatPtr->mChannelsPerFrame = numChannels;
    audioFormatPtr->mBytesPerPacket = 2 * numChannels;
    audioFormatPtr->mFramesPerPacket = 1;
    audioFormatPtr->mBytesPerFrame = 2 * numChannels;
    audioFormatPtr->mBitsPerChannel = 16;
    audioFormatPtr->mFormatFlags = kAudioFormatFlagsNativeEndian |
    kAudioFormatFlagIsPacked | kAudioFormatFlagIsSignedInteger;
}

@end
